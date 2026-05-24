{
  lib,
  config,
  inputs,
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

  mkSkillFiles =
    root: skills:
    lib.mapAttrs' (
      name: source:
      lib.nameValuePair "${root}/${name}" {
        inherit source;
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
      cursor = lib.mkEnableOption "Cursor CLI skill installation";
      gemini = lib.mkEnableOption "Gemini CLI skill installation";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          cfg.targets.antigravity || cfg.targets.codex || cfg.targets.cursor || cfg.targets.gemini;
        message = "local.ai-cli-skills.enable requires at least one enabled target";
      }
    ];

    home.file = lib.mkMerge [
      (lib.mkIf cfg.targets.antigravity (
        (mkSkillFiles ".gemini/antigravity/skills" superpowersSkills)
        // (mkSkillFiles ".gemini/antigravity/skills" androidSkillDirs)
      ))

      (lib.mkIf cfg.targets.codex (
        (mkSkillFiles ".codex/skills" superpowersSkills) // (mkSkillFiles ".codex/skills" androidSkillDirs)
      ))

      (lib.mkIf cfg.targets.cursor (
        (mkSkillFiles ".cursor/skills-cursor" superpowersSkills)
        // (mkSkillFiles ".cursor/skills-cursor" androidSkillDirs)
      ))

      (lib.mkIf cfg.targets.gemini (
        (mkSkillFiles ".gemini/skills" androidSkillDirs)
        // {
          ".gemini/extensions/superpowers" = {
            source = superpowers;
            force = true;
          };
        }
      ))
    ];
  };
}
