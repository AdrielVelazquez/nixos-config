{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.local.pi.routing;
  packageRoot = "${cfg.package}/${cfg.package.packageRoot or "node_modules/pi-subagents"}";
  primary = pkgs.writeText "pi-primary-routing.ts" ''
    import { createRouting } from "${../../dotfiles/pi/extensions/routing.ts}";
    export default pi => createRouting(pi, ${builtins.toJSON { inherit (cfg) agents autoTitle; }});
  '';
  required = pkgs.writeText "pi-required-integrations.ts" ''
    import { fileURLToPath } from "node:url";
    import { requireIntegrations } from "${../../dotfiles/pi/extensions/required-integrations.ts}";
    import { registerRequiredChildExtensions } from "${packageRoot}/src/api/required-child-extensions.js";
    export default pi => requireIntegrations(pi, registerRequiredChildExtensions,
      [{ id: "managed-policy", path: fileURLToPath(import.meta.url) }, ...${builtins.toJSON config.local.pi.requiredChildExtensions}]);
  '';
  readTools = [
    "read"
    "grep"
    "find"
    "ls"
    "codemode"
  ]
  ++ lib.optional config.local.headroom.pi.enable "mcp:headroom/headroom_stats";
  astTools = [
    "ast_grep_run"
    "ast_grep_scan"
    "ast_grep_outline"
    "ast_grep_debug_query"
    "ast_grep_languages"
  ];
  tools =
    name:
    readTools
    ++ lib.optionals (config.local.pi.capabilities.ast.enable && name != "title") astTools
    ++
      lib.optionals
        (
          config.local.pi.capabilities.web.enable
          && lib.elem name [
            "scout"
            "build"
            "plan"
          ]
        )
        [
          "fetch_content"
          "get_search_content"
        ]
    ++ lib.optionals (name == "scout") cfg.scoutMcpTools
    ++ lib.optionals (name == "explore") cfg.exploreMcpTools
    ++
      lib.optionals
        (lib.elem name [
          "build"
          "plan"
        ])
        [
          "write"
          "edit"
          "bash"
          "subagent"
        ];
  roleFile = name: route: ''
    ---
    name: ${name}
    description: ${
      if name == "scout" then
        "External read-only research through approved MCP operations"
      else if name == "explore" then
        "Local read-only repository research"
      else
        "${name} task with explicit model routing"
    }
    model: ${route.model}
    thinking: ${route.thinking}
    tools: ${lib.concatStringsSep ", " (tools name)}
    extensions: []
    inheritProjectContext: true
    inheritGlobalContext: true
    inheritSkills: true
    acceptance: {"level":"none","reason":"Caller owns verification appropriate to the delegated task"}
    ${lib.optionalString (lib.elem name [
      "scout"
      "explore"
      "title"
    ]) "allowNestedSubagents: false"}
    ---
    ${
      if name == "scout" then
        "Research external sources only using available approved read-only MCP tools. Cite what you actually inspected. If none are available, report the limitation; never invent external research."
      else if name == "explore" then
        "Inspect the local repository. Do not modify files, execute shell commands, or delegate to a writer."
      else
        "Perform the delegated ${name} task. Preserve user work and verify claims."
    }
  '';
in
{
  options.local.pi.routing = {
    enable = lib.mkEnableOption "explicit Pi primary and native subagent routing";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../packages/pi-subagents.nix { };
    };
    agents = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            model = lib.mkOption { type = lib.types.strMatching "[^/# ]+/[^# ]+"; };
            thinking = lib.mkOption {
              type = lib.types.enum [
                "off"
                "minimal"
                "low"
                "medium"
                "high"
                "xhigh"
              ];
            };
          };
        }
      );
    };
    autoTitle = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    scoutMcpTools = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "mcp:github/search_code"
        "mcp:github/get_file_contents"
        "mcp:github/search_repositories"
      ];
      description = "Audited read-only operations only; missing tools fail visibly, never broaden to a whole server.";
    };
    exploreMcpTools = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional audited read-only MCP operations, not REPL/shell or wildcard servers.";
    };
  };
  config = lib.mkIf (config.local.pi.enable && cfg.enable) {
    assertions = [
      {
        assertion = lib.all (name: cfg.agents ? ${name}) [
          "build"
          "plan"
          "scout"
          "explore"
          "title"
        ];
        message = "Pi routing requires explicit build/plan/scout/explore/title mappings";
      }
    ];
    local.pi.extraSettings = {
      extensions = [
        "${packageRoot}/index.js"
        "${primary}"
        "${required}"
      ];
      subagents.disableBuiltins = true;
    };
    home.file =
      lib.mapAttrs' (
        name: route:
        lib.nameValuePair "${config.local.pi.agentDir}/agents/${name}.md" { text = roleFile name route; }
      ) cfg.agents
      // {
        "${config.local.pi.agentDir}/extensions/subagent/config.json".text = builtins.toJSON {
          toolActivation = "eager";
          asyncByDefault = false;
          defaultSubagentContext = "fresh";
          maxSubagentDepth = 2;
          intercomBridge.mode = "off";
        };
      };
  };
}
