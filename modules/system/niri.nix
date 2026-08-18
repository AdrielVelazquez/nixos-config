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
  niriPackage = inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri-unstable;
in
{
  imports = [ inputs.niri.nixosModules.niri ];

  options.local.niri.enable = lib.mkEnableOption "niri scrollable-tiling Wayland compositor";

  config = lib.mkMerge [
    {
      niri-flake.cache.enable = false;
      programs.niri.package = niriPackage;
    }
    (lib.mkIf cfg.enable {
      programs.niri.enable = true;

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

      xdg.portal = {
        extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
        config.niri = {
          default = [
            "gnome"
            "gtk"
          ];
          "org.freedesktop.impl.portal.Access" = "gtk";
          "org.freedesktop.impl.portal.FileChooser" = "gtk";
          "org.freedesktop.impl.portal.Notification" = "gtk";
          "org.freedesktop.impl.portal.Secret" = "gnome-keyring";
        };
      };
    })
  ];
}
