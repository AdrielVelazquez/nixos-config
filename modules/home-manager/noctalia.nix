# modules/home-manager/noctalia.nix
#
# Noctalia v5 shell integration. Disabled by default so it can be opted into
# per-user without replacing the existing Waybar/Mako/Swaybg Niri stack.
{
  lib,
  config,
  inputs,
  ...
}:

let
  cfg = config.local.noctalia;
in
{
  imports = [
    inputs.noctalia.homeModules.default
  ];

  options.local.noctalia = {
    enable = lib.mkEnableOption "Noctalia v5 Wayland shell";
  };

  config = lib.mkIf cfg.enable {
    programs.noctalia = {
      enable = true;
    };

    programs.niri.settings.spawn-at-startup = lib.mkAfter [
      { command = [ "noctalia" ]; }
    ];
  };
}
