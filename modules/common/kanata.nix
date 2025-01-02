{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:

with lib;

let
  cfg = config.within.kanata;
in
{
  options.within.kanata.enable = mkEnableOption "Enables kanata Settings";
  config = mkIf cfg.enable {
    environment.etc."mac-kanata.kbd" = {
      source = ../../dotfiles/kanata/config.kdb;
    };
    environment.etc."kanata-nix" = {
      source = ./kanata/kanata_macos_arm64;
    };
    # launchd = {
    #   daemons = {
    #     karabiner-run = {
    #       command = "/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager activate && sudo '/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon'";
    #       serviceConfig = {
    #         KeepAlive = true;
    #         RunAtLoad = true;
    #         ProcessType = "Background";
    #         StandardOutPath = "/tmp/karabiner-run.out.log";
    #         StandardErrorPath = "/tmp/karabiner-run.err.log";
    #       };
    #     };
    #     kanata-run = {
    #       command = "sleep 60 && sudo /etc/kanata-nix -c /etc/mac-kanata.kbd";
    #       serviceConfig = {
    #         KeepAlive = true;
    #         RunAtLoad = true;
    #         ProcessType = "Background";
    #         StandardOutPath = "/tmp/kanata.out.log";
    #         StandardErrorPath = "/tmp/kanata.err.log";
    #       };
    #     };
    #   };
    # };
  };

}
