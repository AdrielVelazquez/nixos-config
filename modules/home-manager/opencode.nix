{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.opencode;
  githubTokenSecretName = "codex_github_token";
  githubTokenEnvVar = "CODEX_GITHUB_PERSONAL_ACCESS_TOKEN";

  opencodeWithGithubToken = pkgs.writeShellScriptBin "opencode" ''
    if [ -z "''${${githubTokenEnvVar}:-}" ] && [ -r "${
      config.sops.secrets.${githubTokenSecretName}.path
    }" ]; then
      export ${githubTokenEnvVar}="$(${pkgs.coreutils}/bin/cat "${
        config.sops.secrets.${githubTokenSecretName}.path
      }")"
    fi

    exec ${pkgs.opencode}/bin/opencode "$@"
  '';
in
{
  options.local.opencode = {
    enable = lib.mkEnableOption "OpenCode CLI";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.${githubTokenSecretName} = { };

    home.packages = [ (lib.hiPrio opencodeWithGithubToken) ];

    home.file.".config/opencode" = {
      source = ../../dotfiles/opencode;
      recursive = true;
    };
  };
}
