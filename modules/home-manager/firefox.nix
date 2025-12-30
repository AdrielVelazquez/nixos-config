# modules/home-manager/firefox.nix
# Firefox with hardware acceleration for AMD GPUs
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.firefox;
in
{
  options.local.firefox = {
    enable = lib.mkEnableOption "Enables Firefox with hardware acceleration";

    enableVaapi = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable VA-API hardware video acceleration";
    };

    useWayland = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable native Wayland support";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.firefox = {
      enable = true;

      # Use Firefox from nixpkgs with VA-API support
      package = pkgs.firefox.override {
        nativeMessagingHosts = [
          # Add any native messaging hosts here if needed
        ];
      };

      profiles.default = {
        isDefault = true;

        settings = lib.mkMerge [
          # Hardware acceleration settings
          (lib.mkIf cfg.enableVaapi {
            # Enable VA-API hardware video decoding
            "media.ffmpeg.vaapi.enabled" = true;

            # Use hardware decoding for supported codecs
            "media.hardware-video-decoding.enabled" = true;
            "media.hardware-video-decoding.force-enabled" = true;

            # WebRender (GPU-accelerated rendering)
            "gfx.webrender.all" = true;
            "gfx.webrender.compositor.force-enabled" = true;

            # GPU process
            "layers.gpu-process.enabled" = true;
            "layers.gpu-process.force-enabled" = true;
          })

          # Wayland-specific settings
          (lib.mkIf cfg.useWayland {
            # Enable DMA-BUF for zero-copy video on Wayland
            "widget.dmabuf.force-enabled" = true;

            # Use Wayland backend
            "widget.use-xdg-desktop-portal.file-picker" = 1;
          })

          # General performance settings
          {
            # Disable Pocket
            "extensions.pocket.enabled" = false;

            # Smoother scrolling
            "general.smoothScroll" = true;
          }
        ];
      };
    };

    # Environment variables for hardware acceleration
    home.sessionVariables = lib.mkMerge [
      (lib.mkIf cfg.enableVaapi {
        # Tell Firefox to use VA-API
        MOZ_DISABLE_RDD_SANDBOX = "1";
        LIBVA_DRIVER_NAME = "radeonsi";
      })

      (lib.mkIf cfg.useWayland {
        # Force Wayland backend
        MOZ_ENABLE_WAYLAND = "1";
      })
    ];

    # Install VA-API drivers and tools
    home.packages = lib.mkIf cfg.enableVaapi (
      with pkgs;
      [
        libva-utils # vainfo command to verify VA-API
      ]
    );
  };
}
