{
  config,
  lib,
  pkgs,
  piLib,
  ...
}:
let
  cfg = config.local.pi.routing;
  packageRoot = "${cfg.package}/${cfg.package.packageRoot or "node_modules/pi-subagents"}";
  entry = pkgs.writeText "pi-subagent-routing.ts" ''
    import subagents from "${packageRoot}/index.js";
    import { setChildSessionFactoryModule } from "${packageRoot}/src/runs/shared/child-session.js";
    setChildSessionFactoryModule(${builtins.toJSON config.local.headroom.pi.backgroundFactory});
    export default subagents;
  '';
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
    import { requireIntegrations } from "${piLib.extensionPath "required-integrations"}";
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
  # Extensions only the file-writing roles load; every other child keeps `extensions: []`.
  childExtensions =
    name:
    lib.optionals (lib.elem name [
      "build"
      "plan"
    ]) cfg.writerExtensions;
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
    extensions: []${
      lib.optionalString (
        childExtensions name != [ ]
      ) "\nsubagentOnlyExtensions: ${lib.concatStringsSep ", " (childExtensions name)}"
    }
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
    enable = lib.mkEnableOption "native Pi subagent routing and required child integrations" // {
      # Routing resolves its task agents through the model roles.
      default = config.local.pi.modelRoles.enable;
      defaultText = lib.literalExpression "config.local.pi.modelRoles.enable";
    };
    entry = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      internal = true;
      default = if config.local.headroom.pi.enable then toString entry else "${packageRoot}/index.js";
      description = "Native subagent entry with optional Pi-only background Headroom acquisition.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../packages/pi-subagents.nix { };
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
    writerExtensions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extension entries loaded only by the build and plan children, which write files. Scout, explore and title never get them.";
    };
    worktreeBaseDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.dataHome}/pi-subagents/worktrees";
      description = "Root of the linked worktrees pi-subagents creates for `worktree: true` children. Outside every repository, so no checkout is dirtied.";
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
        cfg.entry
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
          # Isolation is opt-in per call (`worktree: true`); making it the default would refuse every launch
          # from a tree with untracked files. Worktrunk is not installed, so the native allocator is explicit.
          worktreeProvider = "native";
          worktreeBaseDir = cfg.worktreeBaseDir;
        };
      };
  };
}
