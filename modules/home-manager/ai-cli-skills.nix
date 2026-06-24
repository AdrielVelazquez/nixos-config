{
  lib,
  config,
  inputs,
  pkgs,
  ...
}:

let
  cfg = config.local.ai-cli-skills;

  superpowers = inputs.superpowers;
  androidSkills = inputs.android-skills;

  superpowersSkillNames = [
    "brainstorming"
    "dispatching-parallel-agents"
    "executing-plans"
    "finishing-a-development-branch"
    "receiving-code-review"
    "requesting-code-review"
    "subagent-driven-development"
    "systematic-debugging"
    "test-driven-development"
    "using-git-worktrees"
    "using-superpowers"
    "verification-before-completion"
    "writing-plans"
    "writing-skills"
  ];

  superpowersSkills = lib.genAttrs superpowersSkillNames (name: "${superpowers}/skills/${name}");

  androidSkillPaths = {
    adaptive = "jetpack-compose/adaptive";
    agp-9-upgrade = "build/agp/agp-9-upgrade";
    android-cli = "devtools/android-cli";
    appfunctions = "device-ai/appfunctions";
    camera1-to-camerax = "camera/camera1-to-camerax";
    display-glasses-with-jetpack-compose-glimmer = "xr/display-glasses-with-jetpack-compose-glimmer";
    edge-to-edge = "system/edge-to-edge";
    engage-sdk-integration = "play/engage-sdk-integration";
    migrate-xml-views-to-jetpack-compose = "jetpack-compose/migration/migrate-xml-views-to-jetpack-compose";
    navigation-3 = "navigation/navigation-3";
    perfetto-sql = "profilers/perfetto-sql";
    perfetto-trace-analysis = "profilers/perfetto-trace-analysis";
    play-billing-library-version-upgrade = "play/play-billing-library-version-upgrade";
    r8-analyzer = "performance/r8-analyzer";
    styles = "jetpack-compose/theming/styles";
    testing-setup = "testing/testing-setup";
  };

  androidSkillDirs = lib.mapAttrs (_name: path: "${androidSkills}/${path}") androidSkillPaths;

  recursiveSkillRoots =
    lib.optionals cfg.targets.antigravity [ ".gemini/antigravity/skills" ]
    ++ lib.optionals cfg.targets.codex [ ".codex/skills" ]
    ++ lib.optionals cfg.targets.gemini [ ".gemini/skills" ]
    ++ lib.optionals cfg.targets.opencode [ ".config/opencode/skills" ];

  recursiveSkillTargets = lib.concatMap (
    root: map (name: "${root}/${name}") (lib.attrNames androidSkillDirs)
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

    home.file = lib.mkMerge [
      (lib.mkIf cfg.targets.antigravity (
        (mkSkillFiles ".gemini/antigravity/skills" false superpowersSkills)
        // (mkSkillFiles ".gemini/antigravity/skills" true androidSkillDirs)
      ))

      (lib.mkIf cfg.targets.codex (
        (mkSkillFiles ".codex/skills" false superpowersSkills)
        // (mkSkillFiles ".codex/skills" true androidSkillDirs)
      ))

      (lib.mkIf cfg.targets.gemini (
        (mkSkillFiles ".gemini/skills" true androidSkillDirs)
        // {
          ".gemini/extensions/superpowers" = {
            source = superpowers;
            force = true;
          };
        }
      ))

      (lib.mkIf cfg.targets.opencode (mkSkillFiles ".config/opencode/skills" true androidSkillDirs))
    ];
  };
}
