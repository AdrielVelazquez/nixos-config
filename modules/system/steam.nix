# modules/system/steam.nix
{
  lib,
  config,
  ...
}:

let
  cfg = config.local.steam;
in
{
  options.local.steam.enable = lib.mkEnableOption "Enables Steam gaming platform";

  config = lib.mkIf cfg.enable {
    programs.steam.enable = true;

    # For NVIDIA offload per game, add to Steam launch options:
    # nvidia-offload %command%
  };
}
