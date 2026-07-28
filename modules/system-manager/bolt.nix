# Native bolt setup for non-NixOS hosts managed by system-manager.
{
  lib,
  config,
  ...
}:

let
  cfg = config.local.bolt;
in
{
  options.local.bolt = {
    enable = lib.mkEnableOption "native bolt Thunderbolt authorization service";

    disableThunderboltHostReset = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Set thunderbolt.host_reset=false via modprobe.d.";
    };
  };

  config = lib.mkIf cfg.enable {
    system-manager.preActivationAssertions.boltNativePackage = {
      enable = true;
      script = ''
        missing=0

        for path in /usr/bin/boltctl /usr/lib/boltd /usr/lib/systemd/system/bolt.service; do
          if [ ! -e "$path" ]; then
            echo "Missing native CachyOS bolt component: $path"
            missing=1
          fi
        done

        if [ "$missing" -ne 0 ]; then
          echo "Run 'just bootstrap-cachyos-prereqs' before activating systemConfigs.cachyos-framework."
          exit 1
        fi
      '';
    };

    environment.etc."modprobe.d/99-thunderbolt-studio-display.conf" =
      lib.mkIf cfg.disableThunderboltHostReset
        {
          text = ''
            # MANAGED BY SYSTEM-MANAGER
            # Avoid USB4 host-router resets tearing down the Apple Studio Display DP tunnel.
            options thunderbolt host_reset=false
          '';
        };

  };
}
