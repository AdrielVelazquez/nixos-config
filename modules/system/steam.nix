# modules/system/steam.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.steam;
in
{
  options.local.steam.enable = lib.mkEnableOption "Enables Steam gaming platform";

  config = lib.mkIf cfg.enable {
    programs.steam = {
      enable = true;
      # Run Steam and all games on NVIDIA by default
      # For games you want on AMD, add to launch options:
      # env __NV_PRIME_RENDER_OFFLOAD= __GLX_VENDOR_LIBRARY_NAME= %command%
      package = pkgs.steam.override {
        extraProfile = ''
          # Use NVIDIA for Steam and all games
          export __NV_PRIME_RENDER_OFFLOAD=1
          export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
          export __GLX_VENDOR_LIBRARY_NAME=nvidia
          export __VK_LAYER_NV_optimus=NVIDIA_only
        '';
      };
    };
  };
}
