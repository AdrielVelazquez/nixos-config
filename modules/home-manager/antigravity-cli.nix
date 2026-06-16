{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.local.antigravity-cli;
  antigravityPkgs = import inputs.nixpkgs-antigravity {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
in
{
  options.local.antigravity-cli = {
    enable = lib.mkEnableOption "Antigravity CLI";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ antigravityPkgs.antigravity-cli ];

    local.ai-cli-skills = {
      enable = true;
      targets.antigravity = true;
    };
  };
}
