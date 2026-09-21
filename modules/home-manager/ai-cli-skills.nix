{
  lib,
  config,
  inputs,
  pkgs,
  ...
}:

let
  cfg = config.local.ai-cli-skills;

  skillRoot = "${inputs.compound-engineering}/skills";
  skillNames = lib.filter (name: builtins.pathExists "${skillRoot}/${name}/SKILL.md") (
    lib.attrNames (builtins.readDir skillRoot)
  );
  skillDirs = lib.genAttrs skillNames (name: "${skillRoot}/${name}");

  # Includes retired names and manually installed skills from the old bundle.
  retiredAndroidSkills = [
    "adaptive"
    "agp-9-upgrade"
    "android-cli"
    "android-profiler"
    "appfunctions"
    "camera1-to-camerax"
    "camerax"
    "display-glasses-with-jetpack-compose-glimmer"
    "edge-to-edge"
    "engage-sdk-integration"
    "jetpack-compose-m3"
    "migrate-xml-views-to-jetpack-compose"
    "navigation-3"
    "perfetto-sql"
    "perfetto-trace-analysis"
    "play-billing-library-version-upgrade"
    "r8-analyzer"
    "styles"
    "testing-setup"
    "verified-email"
  ];
  retiredSkillRoots = [
    ".agents/skills"
    ".codex/skills"
    ".gemini/skills"
    ".gemini/antigravity-cli/skills"
    ".config/opencode/skills"
    ".claude/skills"
  ];

  recursiveSkillRoots =
    lib.optionals cfg.targets.antigravity [ ".gemini/antigravity-cli/skills" ]
    ++ lib.optionals cfg.targets.gemini [ ".gemini/skills" ]
    ++ lib.optionals cfg.targets.opencode [ ".config/opencode/skills" ];

  recursiveSkillTargets = lib.concatMap (
    root: map (name: "${root}/${name}") skillNames
  ) recursiveSkillRoots;

  mkSkillFiles =
    root: recursive: skills:
    lib.mapAttrs' (
      name: source:
      lib.nameValuePair "${root}/${name}" {
        inherit source;
        inherit recursive;
        force = true;
      }
    ) skills;
in
{
  options.local.ai-cli-skills = {
    enable = lib.mkEnableOption "shared AI CLI skills";

    targets = {
      antigravity = lib.mkEnableOption "Antigravity CLI skill installation";
      codex = lib.mkEnableOption "Codex skill installation";
      gemini = lib.mkEnableOption "Gemini CLI skill installation";
      opencode = lib.mkEnableOption "OpenCode skill installation";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          cfg.targets.antigravity || cfg.targets.codex || cfg.targets.gemini || cfg.targets.opencode;
        message = "local.ai-cli-skills.enable requires at least one enabled target";
      }
      {
        assertion = skillNames != [ ];
        message = "The pinned Compound Engineering source must contain skills";
      }
    ];

    home.activation.cleanupAiCliSkillDirectorySymlinks = lib.hm.dag.entryBefore [ "checkLinkTargets" ] (
      lib.concatMapStringsSep "\n" (target: ''
        target="${config.home.homeDirectory}/${target}"
        if [ -L "$target" ]; then
          link_target="$(${pkgs.coreutils}/bin/readlink "$target")"
          case "$link_target" in
            /nix/store/*-home-manager-files/*)
              $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm -f "$target"
              ;;
          esac
        fi
      '') recursiveSkillTargets
    );

    home.activation.removeRetiredAndroidSkills = lib.hm.dag.entryAfter [ "linkGeneration" ] (
      lib.concatMapStringsSep "\n" (
        root:
        lib.concatMapStringsSep "\n" (name: ''
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm -rf -- ${lib.escapeShellArg "${config.home.homeDirectory}/${root}/${name}"}
        '') retiredAndroidSkills
      ) retiredSkillRoots
    );

    # Codex installs the native plugin in codex-cli.nix. Other clients discover
    # these same self-contained skills from their native skill directories.
    home.file = lib.mkMerge [
      (lib.mkIf cfg.targets.antigravity (mkSkillFiles ".gemini/antigravity-cli/skills" true skillDirs))

      (lib.mkIf cfg.targets.gemini (mkSkillFiles ".gemini/skills" true skillDirs))

      (lib.mkIf cfg.targets.opencode (mkSkillFiles ".config/opencode/skills" true skillDirs))
    ];
  };
}
