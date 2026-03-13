# modules/system-manager/niri.nix
# System-level niri concerns for non-NixOS (e.g. CachyOS via system-manager)
{
  lib,
  config,
  ...
}:

let
  cfg = config.local.niri;
in
{
  options.local.niri.enable = lib.mkEnableOption "niri system-level support (PAM for swaylock, etc.)";

  config = lib.mkIf cfg.enable {
    environment.etc."pam.d/swaylock".text = ''
      auth include system-auth
    '';
  };
}
