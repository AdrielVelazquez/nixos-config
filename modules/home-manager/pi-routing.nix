{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.local.pi.routing;
  packageRoot = "${cfg.package}/${cfg.package.packageRoot or "node_modules/pi-subagents"}";
  roles = config.local.pi.modelRoles.roles;
  taskAgents = config.local.pi.modelRoles.taskAgents;
  inherits = {
    smol = "default";
    slow = "default";
    plan = "slow";
    advisor = "slow";
    commit = "smol";
    tiny = "smol";
    widget = "smol";
    memory = "tiny";
    task = "default";
    vision = "default";
  };
  resolveRole =
    seen: name:
    if lib.elem name seen then
      throw "Pi task role alias cycle: ${lib.concatStringsSep " -> " (seen ++ [ name ])}"
    else if (roles.${name} or null) != null then
      resolveSelector (seen ++ [ name ]) roles.${name}
    else if name == "default" then
      throw "Pi task agents require a non-null default model selector"
    else
      resolveRole (seen ++ [ name ]) (inherits.${name} or "default");
  resolveSelector =
    seen: selector:
    let
      candidate = lib.strings.trim (builtins.head (lib.splitString "," selector));
      parts = lib.splitString ":" candidate;
      reference = builtins.head parts;
      thinking = if builtins.length parts == 2 then builtins.elemAt parts 1 else null;
      target =
        if lib.hasPrefix "@" reference then
          resolveRole seen (lib.removePrefix "@" reference)
        else if builtins.match "[^/ :]+/[^ :]+" reference != null then
          {
            model = reference;
            thinking = config.local.pi.extraSettings.defaultThinkingLevel or "off";
          }
        else
          throw "Invalid Pi task model selector: ${selector}";
    in
    if
      builtins.length parts > 2
      || (
        thinking != null
        && !(lib.elem thinking [
          "off"
          "minimal"
          "low"
          "medium"
          "high"
          "xhigh"
          "max"
          "inherit"
        ])
      )
    then
      throw "Invalid Pi task thinking suffix: ${selector}"
    else
      target // lib.optionalAttrs (thinking != null && thinking != "inherit") { inherit thinking; };
  routes = builtins.mapAttrs (_: resolveSelector [ ]) taskAgents;
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
          "web_search"
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
    enable = lib.mkEnableOption "native Pi subagent routing and required child integrations";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../packages/pi-subagents.nix { };
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
        assertion = lib.all (name: taskAgents ? ${name}) [
          "build"
          "plan"
          "scout"
          "explore"
          "title"
        ];
        message = "Pi routing requires modelRoles.taskAgents build/plan/scout/explore/title selectors";
      }
    ];
    local.pi.extraSettings = {
      extensions = [
        "${packageRoot}/index.js"
        "${required}"
      ];
      subagents.disableBuiltins = true;
    };
    home.file =
      lib.mapAttrs' (
        name: route:
        lib.nameValuePair "${config.local.pi.agentDir}/agents/${name}.md" { text = roleFile name route; }
      ) routes
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
