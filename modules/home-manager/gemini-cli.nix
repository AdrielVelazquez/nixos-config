# modules/home-manager/gemini-cli.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.gemini-cli;
  jsonFormat = pkgs.formats.json { };

  githubMcpWrapper = pkgs.writeShellScriptBin "github-mcp-wrapper" ''
    export GITHUB_PERSONAL_ACCESS_TOKEN="$(${pkgs.coreutils}/bin/cat ${config.sops.secrets.github_token.path})"
    exec ${pkgs.nodejs}/bin/npx -y @modelcontextprotocol/server-github "$@"
  '';

  settings = {
    security.auth.selectedType = "oauth-personal";
    mcpServers = {
      github = {
        command = "${githubMcpWrapper}/bin/github-mcp-wrapper";
        args = [ ];
      };
    };
  };
in
{
  options.local.gemini-cli = {
    enable = lib.mkEnableOption "Enables gemini-cli";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.github_token = { };

    home.packages = [ pkgs.gemini-cli ];

    home.file.".gemini/settings.json" = {
      source = jsonFormat.generate "gemini-settings.json" settings;
      force = true;
    };

    local.ai-cli-skills = {
      enable = true;
      targets.gemini = true;
    };
  };
}
