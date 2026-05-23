# modules/services/mullvad.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.mullvad;
in
{
  options.local.mullvad = {
    enable = lib.mkEnableOption "Enables Mullvad VPN";
    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether the Mullvad daemon should start automatically at boot.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.mullvad-vpn = {
      enable = true;
      package = pkgs.mullvad-vpn;
    };

    systemd.services.mullvad-daemon.wantedBy = lib.mkIf (!cfg.autoStart) (lib.mkForce [ ]);
  };
}
