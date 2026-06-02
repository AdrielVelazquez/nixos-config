{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.nixpkgs-review;
in
{
  options.local.nixpkgs-review = {
    enable = lib.mkEnableOption "nixpkgs-review";

    githubTokenSecret = lib.mkOption {
      type = lib.types.str;
      default = "github_token";
      description = "SOPS secret name used by nixpkgs-review for GitHub API access.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.${cfg.githubTokenSecret} = { };

    home.packages = with pkgs; [
      nixpkgs-review
      nix-output-monitor
      glow
    ];

    home.sessionVariables = {
      GITHUB_TOKEN_CMD = "${pkgs.coreutils}/bin/cat ${config.sops.secrets.${cfg.githubTokenSecret}.path}";
    };
  };
}
