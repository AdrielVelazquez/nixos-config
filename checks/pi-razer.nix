{
  lib,
  pkgs,
  razerHome,
  ...
}:
let
  agentDir = razerHome.local.pi.agentDir;
  fixture = pkgs.writeText "pi-razer-fixture.json" (
    builtins.toJSON {
      settings = razerHome.programs.pi-coding-agent.settings;
      roles = razerHome.local.pi.modelRoles.roles;
      taskAgents = razerHome.local.pi.modelRoles.taskAgents;
      providers = razerHome.local.headroom.pi.providers;
      apiKeys = razerHome.local.pi.apiKeys;
      modelsFile = toString razerHome.home.file."${agentDir}/models.json".source;
      llmPlatform = razerHome.local.pi.llmPlatform.enable;
      headroom = razerHome.local.headroom.pi.enable;
      routing = razerHome.local.pi.routing.enable;
      required = map (entry: entry.id) razerHome.local.pi.requiredChildExtensions;
      agents = lib.genAttrs (builtins.attrNames razerHome.local.pi.modelRoles.taskAgents) (
        name: razerHome.home.file."${agentDir}/agents/${name}.md".text or null
      );
      mcpFile = toString razerHome.home.file."${agentDir}/mcp.json".source;
    }
  );
  catalog = "${pkgs.pi-coding-agent}/lib/node_modules/pi-monorepo/node_modules/@earendil-works/pi-ai/dist/providers/data";
in
{
  pi-razer = pkgs.runCommand "pi-razer-contract" { nativeBuildInputs = [ pkgs.nodejs_24 ]; } ''
    node ${../tests/pi/razer-contract.mjs} ${fixture} ${catalog}
    touch "$out"
  '';
}
