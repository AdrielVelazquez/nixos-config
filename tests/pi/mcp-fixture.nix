{
  root ? ../..,
}:
let
  f = builtins.getFlake (toString root);
  base = f.homeConfigurations.cachyos-framework13;
  pkgs = base.pkgs;
  probe = pkgs.writeShellScriptBin "pi" ''
    exec ${pkgs.python3.interpreter} -E ${./mcp-probe.py} ${
      fixture.home.file."/home/adriel/.pi/agent/mcp.json".source
    }
  '';
  fixture =
    (base.extendModules {
      modules = [
        {
          local.pi = {
            enable = true;
            package = probe;
            llmPlatform = {
              enable = true;
              package = f.inputs.pi-reddit-provider.outPath;
            };
            mcpServers.github.enabled = false;
          };
          local.headroom.pi = {
            enable = true;
            memory = true;
            codeGraph = true;
            serena.enable = true;
          };
        }
      ];
    }).config;
in
fixture.programs.pi-coding-agent.package
