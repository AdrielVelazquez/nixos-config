# modules/home-manager/gemini-cli.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.gemini-cli;
  headroomCfg = config.local.headroom;
  headroomEnabled = headroomCfg.enable && (headroomCfg.agents.gemini or false);
  jsonFormat = pkgs.formats.json { };

  geminiPackage =
    if headroomEnabled then
      pkgs.writeShellScriptBin "gemini" ''
        # Gemini's native GOOGLE_GEMINI_BASE_URL is not OpenAI-compatible;
        # keep this wrapper lifecycle-only until Headroom exposes a safe Gemini endpoint.
        exec ${headroomCfg.sessionHelper}/bin/headroom-agent-session gemini -- ${pkgs.gemini-cli}/bin/gemini "$@"
      ''
    else
      pkgs.gemini-cli;

  githubMcpWrapper = pkgs.writeShellScriptBin "github-mcp-wrapper" ''
    # config.sops.secrets...path automatically points to the correct 
    # location (usually /run/user/1000/secrets/github_token in HM)
    export GITHUB_PERSONAL_ACCESS_TOKEN=$(cat ${config.sops.secrets.github_token.path})
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

    # 1. Define the secret
    sops.secrets.github_token = {
      # In Home Manager, 'owner' is not needed/supported.
      # The secret is automatically owned by config.home.username.
      # Just ensure your sops.yaml file has a key for this user.
    };

    home.packages = [ (lib.hiPrio geminiPackage) ];

    # Gemini CLI writes to ~/.gemini/settings.json; force prevents backup clashes
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
