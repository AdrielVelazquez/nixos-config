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

    security.pam.services.hyprlock = { };

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
      ELECTRON_OZONE_PLATFORM_HINT = "wayland";
      XDG_CURRENT_DESKTOP = "niri";
      XDG_SESSION_TYPE = "wayland";
    };
  };
}
