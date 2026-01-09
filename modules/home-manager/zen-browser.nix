# modules/home-manager/zen-browser.nix
# Zen Browser with hardware acceleration for AMD GPUs
{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.local.zen-browser;
in
{
  imports = [
    inputs.zen-browser.homeModules.default
  ];

  options.local.zen-browser = {
    enable = lib.mkEnableOption "Enables Zen Browser with hardware acceleration";

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

    disableGpuCompositing = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Disable GPU compositing/WebRender (nuclear option for freeze issues)";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.zen-browser = {
      enable = true;

      # Policies (admin-level settings)
      policies = {
        DisableTelemetry = true;
        DisableFirefoxStudies = true;
        EnableTrackingProtection = {
          Value = true;
          Locked = true;
        };
        DisablePocket = true;
        DisableFirefoxAccounts = false; # Keep Firefox sync enabled
        DisableAccounts = false;
        DisableFirefoxScreenshots = true;
        OverrideFirstRunPage = "";
        OverridePostUpdatePage = "";
        DontCheckDefaultBrowser = true;
        DisplayMenuBar = "default-off";
        SearchBar = "unified";
      };

      profiles.default = {
        isDefault = true;

        settings = lib.mkMerge [
          # Hardware acceleration settings
          (lib.mkIf cfg.enableVaapi {
            "media.ffmpeg.vaapi.enabled" = true;
            "media.hardware-video-decoding.enabled" = true;
            # Removed force-enabled - let browser auto-detect to prevent freezes
            # "media.hardware-video-decoding.force-enabled" = true;

            "gfx.webrender.all" = true;
            # Removed compositor force - this can cause black screens on long sessions
            # "gfx.webrender.compositor.force-enabled" = true;

            "layers.gpu-process.enabled" = true;
            # Removed force-enabled - can cause instability
            # "layers.gpu-process.force-enabled" = true;

            # Memory management to prevent long-session freezes
            "browser.sessionhistory.max_total_viewers" = 4; # Limit cached pages
            "browser.cache.memory.capacity" = 256000; # Cap memory cache at ~250MB
            "javascript.options.mem.gc_incremental" = true; # Smoother GC

            # GPU process recovery settings
            "gfx.webrender.fallback.basic" = true; # Fallback if WebRender fails
          })

          # Wayland-specific settings
          (lib.mkIf cfg.useWayland {
            # Removed force-enabled - can cause black screens on some GPU states
            # "widget.dmabuf.force-enabled" = true;
            "widget.use-xdg-desktop-portal.file-picker" = 1;

            # Enable dmabuf without forcing (browser will auto-detect compatibility)
            "widget.dmabuf-webgl.enabled" = true;
          })

          # Stability fixes for long sessions / sleep-wake cycles
          {
            # Disable window occlusion tracking - prevents rendering from "sleeping"
            # and failing to wake up after long sessions or system sleep
            "widget.windows.window_occlusion_tracking.enabled" = false;

            # Zen-specific: ensure workspaces are not in testing/disabled mode
            "zen.workspaces.disabled_for_testing" = false;

            # Increase GPU process timeout before killing (default is 30000ms)
            "layers.gpu-process.crash.timeout_ms" = 60000;

            # Disable compositor suspend to prevent wake-up failures
            "dom.ipc.plugins.content.parent.main_thread_timeout_ms" = 0;

            # Prevent content process hangs from freezing UI
            "dom.ipc.cpow.timeout" = 0;
          }

          # Nuclear option: disable GPU compositing entirely
          (lib.mkIf cfg.disableGpuCompositing {
            "gfx.webrender.all" = false;
            "gfx.webrender.enabled" = false;
            "layers.acceleration.disabled" = true;
            "layers.gpu-process.enabled" = false;
            "media.hardware-video-decoding.enabled" = false;
          })

          # General settings
          {
            # Enable gradient zen themes for OLED
            "zen.theme.gradient" = true;
            "zen.theme.gradient.show-custom-colors" = true;

            # Disable Pocket
            "extensions.pocket.enabled" = false;

            # Smoother scrolling
            "general.smoothScroll" = true;

            # Privacy & Performance
            "privacy.trackingprotection.enabled" = true;
            "dom.security.https_only_mode" = true;

            # Disable "More from Mozilla"
            "browser.preferences.moreFromMozilla" = false;

            # DRM / Netflix Support
            "media.eme.enabled" = true;
            "media.gmp-widevinecdm.enabled" = true;
            "media.gmp-widevinecdm.visible" = true;
            "media.autoplay.default" = 1;

            # Clean new tab page
            "browser.newtabpage.activity-stream.showSponsored" = false;
            "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
            "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
            "browser.newtabpage.activity-stream.feeds.topsites" = false;

            # Disable URL bar suggestions clutter
            "browser.urlbar.suggest.engines" = false;
            "browser.urlbar.suggest.topsites" = false;
            "browser.urlbar.trending.featureGate" = false;
            "browser.urlbar.quicksuggest.enabled" = false;

            # Disable extension recommendations
            "extensions.htmlaboutaddons.recommendations.enabled" = false;

            # Disable What's New
            "browser.messaging-system.whatsNewPanel.enabled" = false;
          }
        ];
      };
    };

    # Environment variables for hardware acceleration
    home.sessionVariables = lib.mkMerge [
      (lib.mkIf cfg.enableVaapi {
        MOZ_DISABLE_RDD_SANDBOX = "1";
        LIBVA_DRIVER_NAME = "radeonsi";
      })

      (lib.mkIf cfg.useWayland {
        MOZ_ENABLE_WAYLAND = "1";
      })
    ];

    # Install VA-API drivers and tools
    home.packages = lib.mkIf cfg.enableVaapi [
      pkgs.libva-utils
    ];
  };
}
