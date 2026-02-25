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

    enableGpuRecovery = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable aggressive GPU process recovery for compositors that invalidate GPU contexts on sleep/lock (e.g. COSMIC)";
    };
  };

  config = lib.mkIf cfg.enable {
    home.file."${config.xdg.configHome}/zen/profiles.ini".force = true;

    programs.zen-browser.suppressXdgMigrationWarning = true;
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
        path = "default"; # Pin profile directory to prevent resets on flake updates

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
            # Window occlusion tracking - KEEP ENABLED (default)
            # Disabling this can cause UI elements like sidebars to disappear
            # because the browser misjudges window visibility
            # "widget.windows.window_occlusion_tracking.enabled" = false; # REMOVED - causes sidebar vanishing

            # Zen-specific: ensure workspaces are not in testing/disabled mode
            "zen.workspaces.disabled_for_testing" = false;

            # Increase GPU process timeout before killing (default is 30000ms)
            "layers.gpu-process.crash.timeout_ms" = 60000;

            # Timeout settings - REMOVED aggressive zero timeouts
            # These can interfere with sidebar rendering and UI responsiveness
            # "dom.ipc.plugins.content.parent.main_thread_timeout_ms" = 0; # REMOVED
            # "dom.ipc.cpow.timeout" = 0; # REMOVED
          }

          # GPU process recovery for compositors that drop GPU contexts on sleep
          (lib.mkIf cfg.enableGpuRecovery {
            "gfx.gpu-process.allow-restart" = true;
            "gfx.gpu-process.max_restarts" = 6;
            "gfx.gpu-process.max_restarts_with_decoder" = 6;
            "widget.gpu-process-detect-hang" = true;
            "layers.gpu-process.crash.timeout_ms" = lib.mkForce 120000;
            "gfx.canvas.remote.allow-in-parent" = true;
          })

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

            # DRM / Streaming Support (Netflix, Disney+, etc.)
            "media.eme.enabled" = true;
            "media.gmp-widevinecdm.enabled" = true;
            "media.gmp-widevinecdm.visible" = true;
            "media.autoplay.default" = 1;

            # Higher quality video streaming
            "media.mediasource.enabled" = true;
            "media.mediasource.webm.enabled" = true;
            "media.mediasource.vp9.enabled" = true;
            "media.av1.enabled" = true; # AV1 codec for YouTube/Netflix 4K
            "media.webm.enabled" = true;

            # Allow higher resolution video
            "privacy.resistFingerprinting" = false; # Must be false for HD streaming
            "media.video_stats.enabled" = true; # Required for adaptive bitrate

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
