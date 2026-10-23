{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.local.pi.modelRoles;
  defaultRoles = {
    default = "llm-platform/gpt-6.1-sol:high";
    plan = "llm-platform/claude-sonnet-5-5:xhigh";
    slow = "llm-platform/claude-sonnet-5-5:xhigh";
    smol = "llm-platform/gpt-6-luna:low";
    commit = "llm-platform/gpt-6-luna:low";
    memory = "llm-platform/gpt-6-luna:low";
    widget = "llm-platform/gpt-6-luna:low";
    tiny = "llm-platform/gpt-6-luna:off";
    task = "llm-platform/gpt-6.1-sol:high";
    advisor = "llm-platform/claude-sonnet-5-5:xhigh";
    vision = null;
  };
  defaultAgents = {
    build = "@default";
    plan = "@plan";
    scout = "llm-platform/gpt-6.1-sol:low";
    explore = "llm-platform/gpt-6-luna:low";
    title = "@tiny";
  };
  defaults = {
    modelRoles = cfg.roles;
    retry = { inherit (cfg) modelFallback cooldownMs fallbackChains; };
    inherit (cfg)
      cycleOrder
      autoTitle
      compactionRole
      planMode
      ;
    task.agentModelOverrides = cfg.taskAgents;
    agents = lib.genAttrs (builtins.attrNames cfg.taskAgents) (name: {
      description = "${name} task with explicit model routing";
      prompt = "Perform the delegated ${name} task. Preserve user work and verify claims.";
    });
  };
  entry = pkgs.writeText "pi-model-roles.ts" ''
    import { createModelRoles } from "${../../dotfiles/pi/extensions}/model-roles.ts";
    export default pi => createModelRoles(pi, ${builtins.toJSON defaults});
  '';
in
{
  options.local.pi.modelRoles = {
    enable = lib.mkEnableOption "consumer-backed Pi model roles and writable role overlay";
    roles = lib.mkOption {
      type = lib.types.attrsOf (lib.types.nullOr lib.types.str);
      default = { };
      description = "Exact provider/model[:thinking], comma availability alternatives, or @role aliases.";
    };
    fallbackChains = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
    };
    modelFallback = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
    cooldownMs = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 60000;
    };
    cycleOrder = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "smol"
        "default"
        "slow"
      ];
    };
    autoTitle = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    compactionRole = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Null preserves the physical model of the active conversation for compaction.";
    };
    planMode = {
      readOnly = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      tools = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "read"
          "grep"
          "find"
          "ls"
          "question"
          "ast_grep_run"
          "ast_grep_scan"
          "ast_grep_outline"
          "ast_grep_debug_query"
          "ast_grep_languages"
          "fetch_content"
          "get_search_content"
          "web_search"
        ];
        description = "Exact tool allowlist, used only when readOnly is true.";
      };
    };
    taskAgents = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Immutable subagent selectors; Nix resolves aliases and uses the first comma alternative.";
    };
    entries = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      default = lib.optionalAttrs cfg.enable { modelRoles = "${entry}"; };
    };
  };
  config = lib.mkMerge [
    {
      local.pi.modelRoles = {
        roles = lib.mapAttrs (_: lib.mkDefault) defaultRoles;
        taskAgents = lib.mapAttrs (_: lib.mkDefault) defaultAgents;
      };
    }
    (lib.mkIf (config.local.pi.enable && cfg.enable) {
      local.pi.extraSettings = {
        defaultProvider = lib.mkForce "roles";
        defaultModel = lib.mkForce "auto";
        extensions = [ "${entry}" ];
      };
    })
  ];
}
