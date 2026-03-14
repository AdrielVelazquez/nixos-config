# modules/system/niri.nix
{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.local.niri;
in
{
  imports = [ inputs.niri.nixosModules.niri ];

  options.local.niri.enable = lib.mkEnableOption "niri scrollable-tiling Wayland compositor";

  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = [ inputs.niri.overlays.niri ];

    programs.niri.enable = true;
    programs.niri.package = pkgs.niri-unstable.overrideAttrs { doCheck = false; };

    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd niri-session";
          user = "greeter";
        };
      };
    };

    environment.sessionVariables = {
      NIXOS_OZONE_WL = "1";
      XDG_CURRENT_DESKTOP = "niri";
      XDG_SESSION_TYPE = "wayland";
      # Force Mesa EGL for all session processes so Wayland clients don't
      # load NVIDIA's EGL vendor (10_nvidia.json has higher priority by default).
      __EGL_VENDOR_LIBRARY_FILENAMES = "/run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json";
    };
  };
}
