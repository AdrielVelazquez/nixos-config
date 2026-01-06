# modules/home-manager/floorp.nix
# Floorp with hardware acceleration for AMD GPUs
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.floorp;
in
{
  options.local.floorp = {
    enable = lib.mkEnableOption "Enables Floorp with hardware acceleration";

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
    programs.floorp = {
      enable = true;

      # Policies: "Hard" limits (Admin level).
      # Great for disabling the "bloat".
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

            # Privacy & Performance
            "privacy.trackingprotection.enabled" = true;
            "dom.security.https_only_mode" = true;

            # Vertical Tabs
            "sidebar.verticalTabs" = true;
            "floorp.browser.tabs.vertical" = true;

            # Disable Floorp Panel Sidebar (Google Translate, Floorp Notes, etc.)
            "floorp.panelSidebar.enabled" = false;

            # Hide bookmarks toolbar
            # Options: "never", "newtab", "always"
            "browser.toolbars.bookmarks.visibility" = "never";

            # ===== Zen-like Minimal UI =====

            # Compact mode (smaller UI density)
            "browser.uidensity" = 1; # 0=normal, 1=compact, 2=touch

            # Compact sidebar (collapsed by default, expands on hover)
            "sidebar.revamp" = true;

            # Hide titlebar for cleaner look
            "browser.tabs.inTitlebar" = 1;

            # Cleaner new tab page
            "browser.newtabpage.activity-stream.showSponsored" = false;
            "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
            "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
            "browser.newtabpage.activity-stream.feeds.topsites" = false;
            "browser.newtabpage.activity-stream.section.highlights.includeBookmarks" = false;
            "browser.newtabpage.activity-stream.section.highlights.includeDownloads" = false;
            "browser.newtabpage.activity-stream.section.highlights.includePocket" = false;
            "browser.newtabpage.activity-stream.section.highlights.includeVisited" = false;

            # Disable URL bar suggestions clutter
            "browser.urlbar.suggest.engines" = false;
            "browser.urlbar.suggest.topsites" = false;
            "browser.urlbar.trending.featureGate" = false;
            "browser.urlbar.quicksuggest.enabled" = false;

            # Disable extension recommendations
            "extensions.htmlaboutaddons.recommendations.enabled" = false;

            # Disable What's New and other notifications
            "browser.messaging-system.whatsNewPanel.enabled" = false;

            # Disable "More from Mozilla"
            "browser.preferences.moreFromMozilla" = false;

            # DRM / Netflix Support
            # Master Switch: Enable DRM
            "media.eme.enabled" = true;

            # Force the Widevine CDM (Content Decryption Module) to load
            "media.gmp-widevinecdm.enabled" = true;
            "media.gmp-widevinecdm.visible" = true;

            # Autoplay for DRM content (Netflix annoyance fix)
            # 0=Allowed, 1=Blocked, 5=AllBlocked
            "media.autoplay.default" = 1;

            # Enable userChrome.css customization
            "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
          }
        ];

        # Zen-like userChrome.css
        # Hides the horizontal tab bar (since we use vertical tabs)
        # and creates a cleaner, more minimal interface
        userChrome = ''
          /* ===== Zen-like Minimal UI ===== */

          /* Hide horizontal tab bar (using vertical tabs instead) */
          #TabsToolbar {
            visibility: collapse !important;
          }

          /* Make the navbar more compact */
          #nav-bar {
            padding-block: 2px !important;
            margin-top: -1px !important;
          }

          /* Compact URL bar */
          #urlbar-container {
            max-width: 70% !important;
          }

          /* Hide window controls when using vertical tabs sidebar */
          .titlebar-buttonbox-container {
            display: none !important;
          }

          /* Cleaner sidebar appearance */
          #sidebar-header {
            display: none !important;
          }

          /* Remove border between sidebar and content */
          #sidebar-splitter {
            border: none !important;
            width: 1px !important;
            background: transparent !important;
          }

          /* Subtle toolbar background */
          #navigator-toolbox {
            border-bottom: none !important;
          }

          /* Rounded corners on URL bar for modern look */
          #urlbar-background {
            border-radius: 8px !important;
          }

          /* Hide the "all tabs" button (not needed with vertical tabs) */
          #alltabs-button {
            display: none !important;
          }
        '';
      };
    };

    # Environment variables for hardware acceleration
    home.sessionVariables = lib.mkMerge [
      (lib.mkIf cfg.enableVaapi {
        # Tell Firefox-based browsers to use VA-API
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
