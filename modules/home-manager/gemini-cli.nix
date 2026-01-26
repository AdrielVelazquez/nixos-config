# modules/home-manager/gemini-cli.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.gemini-cli;

  githubMcpWrapper = pkgs.writeShellScriptBin "github-mcp-wrapper" ''
    # config.sops.secrets...path automatically points to the correct 
    # location (usually /run/user/1000/secrets/github_token in HM)
    export GITHUB_PERSONAL_ACCESS_TOKEN=$(cat ${config.sops.secrets.github_token.path})
    exec ${pkgs.nodejs}/bin/npx -y @modelcontextprotocol/server-github "$@"
  '';
in
{
  options.local.gemini-cli = {
    enable = lib.mkEnableOption "Enables gemini-cli";
  };

  config = lib.mkIf cfg.enable {

    # 1. Define the secret
    sops.secrets.github_token = {
      # In Home Manager, 'owner' is not needed/supported.
      # The secret is automatically owned by config.home.username.
      # Just ensure your sops.yaml file has a key for this user.
    };

    # 2. Configure Gemini CLI
    programs.gemini-cli = {
      enable = true;
      settings = {
        model = "gemini-3-pro-preview";
        mcpServers = {
          github = {
            command = "${githubMcpWrapper}/bin/github-mcp-wrapper";
            args = [ ];
          };
        };
      };
    };

    # Gemini CLI writes to ~/.gemini/settings.json; force prevents backup clashes
    home.file.".gemini/settings.json".force = true;
  };
}
