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
    programs.niri.enable = true;

    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --cmd niri-session";
          user = "greeter";
        };
      };
    };

    environment.sessionVariables = {
      NIXOS_OZONE_WL = "1";
      XDG_CURRENT_DESKTOP = "niri";
      XDG_SESSION_TYPE = "wayland";
    };
  };
}
