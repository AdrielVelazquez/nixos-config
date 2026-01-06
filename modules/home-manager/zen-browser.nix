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
            "media.hardware-video-decoding.force-enabled" = true;
            "gfx.webrender.all" = true;
            "gfx.webrender.compositor.force-enabled" = true;
            "layers.gpu-process.enabled" = true;
            "layers.gpu-process.force-enabled" = true;
          })

          # Wayland-specific settings
          (lib.mkIf cfg.useWayland {
            "widget.dmabuf.force-enabled" = true;
            "widget.use-xdg-desktop-portal.file-picker" = 1;
          })

          # General settings
          {
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
