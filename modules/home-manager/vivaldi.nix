# modules/home-manager/vivaldi.nix
# Vivaldi Browser with hardware acceleration
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.vivaldi;
in
{
  options.local.vivaldi = {
    enable = lib.mkEnableOption "Enables Vivaldi Browser with hardware acceleration";

    enableVaapi = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable VA-API hardware video acceleration";
    };

    useWayland = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable native Wayland support via Ozone";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages =
      let
        # Build command-line flags based on options
        flags = lib.concatStringsSep " " (
          lib.flatten [
            # Hardware acceleration
            (lib.optionals cfg.enableVaapi [
              "--enable-features=VaapiVideoDecoder,VaapiVideoEncoder,VaapiVideoDecodeLinuxGL"
              "--enable-gpu-rasterization"
              "--enable-zero-copy"
              "--ignore-gpu-blocklist"
            ])

            # Wayland native support
            (lib.optionals cfg.useWayland [
              "--ozone-platform=wayland"
              "--enable-features=UseOzonePlatform"
              "--enable-wayland-ime"
            ])

            # General GPU acceleration
            "--enable-accelerated-video-decode"
          ]
        );

        # Wrap vivaldi with hardware acceleration flags
        vivaldi-wrapped = pkgs.symlinkJoin {
          name = "vivaldi-wrapped";
          paths = [ pkgs.vivaldi ];
          buildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
            wrapProgram $out/bin/vivaldi \
              --add-flags "${flags}"
          '';
        };
      in
      [
        vivaldi-wrapped
        pkgs.vivaldi-ffmpeg-codecs # Proprietary codecs for video playback
      ]
      ++ lib.optionals cfg.enableVaapi [
        pkgs.libva-utils # VA-API diagnostic tools
      ];

    # Environment variables for hardware acceleration
    home.sessionVariables = lib.mkIf cfg.enableVaapi {
      # Use radeonsi VA-API driver for AMD
      LIBVA_DRIVER_NAME = "radeonsi";
    };
  };
}
