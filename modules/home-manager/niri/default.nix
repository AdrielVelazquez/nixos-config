# modules/home-manager/niri/default.nix
{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.local.niri;
  style = cfg.style;
  wallpaper = ../../../assets/astronaut_oled_fixed.png;
  scripts = import ./scripts.nix { inherit lib config pkgs; };
  niriPackage = inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri-unstable;
in
{
  imports = [
    ./style.nix
    ./waybar.nix
    ./mako.nix
    ./hyprlock.nix
    ./wallpaper.nix
    ./fuzzel.nix
    ./theme.nix
    ./services.nix
  ];

  options.local.niri = {
    enable = lib.mkEnableOption "niri Wayland compositor user configuration";
    renderDevice = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/dev/dri/by-path/pci-0000:c5:00.0-render";
      description = "DRM render device for niri to use as primary GPU. Useful for multi-GPU laptops to force the iGPU.";
    };
    ignoreDrmDevice = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/dev/dri/by-path/pci-0000:c4:00.0-card";
      description = "DRM primary (card) device for niri to completely ignore. Use the -card node to block KMS probing and let the dGPU enter D3cold.";
    };
    brightnessDevice = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "amdgpu_bl1";
      description = "Backlight device name for brightnessctl to target explicitly. Useful on hybrid-GPU laptops where the default device may be the wrong GPU.";
    };
    appleStudioDisplay.enable = lib.mkEnableOption "Apple Studio Display brightness integration";
    hasDgpu = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Deprecated compatibility toggle for systems with an NVIDIA discrete GPU. Set local.niri.dgpuPciPath to enable the dGPU power-state indicator.";
    };
    dgpuPciPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/sys/bus/pci/devices/0000:c4:00.0";
      description = "PCI sysfs path for the NVIDIA dGPU status widget. Set to null to disable it.";
    };
    useSystemHyprlock = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Use the system-installed hyprlock instead of the nix package. Required on non-NixOS where nix-built PAM binaries can't verify passwords (unix_chkpwd lacks setuid in the nix store).";
    };
    wallpaper = lib.mkOption {
      type = lib.types.path;
      default = wallpaper;
      description = "Path to wallpaper image for the static wallpaper service.";
    };
  };

  config = lib.mkIf cfg.enable {
    warnings = lib.optional (cfg.hasDgpu && cfg.dgpuPciPath == null) ''
      local.niri.hasDgpu is deprecated and no longer enables the dGPU widget by itself.
      Set local.niri.dgpuPciPath to the NVIDIA PCI sysfs path instead.
    '';

    local.niri = {
      hyprlock.enable = lib.mkDefault true;
      waybar.enable = lib.mkDefault true;
      services.enable = lib.mkDefault true;
      mako.enable = lib.mkDefault true;
      theme.enable = lib.mkDefault true;
      fuzzel.enable = lib.mkDefault true;
      wallpaperService.enable = lib.mkDefault true;
    };
    local.yazi.enable = lib.mkDefault true;
    local.web-mime-defaults.fileManager = lib.mkDefault "com.system76.CosmicFiles.desktop";

    xdg.configFile."xdg-desktop-portal/niri-portals.conf".text = ''
      [preferred]
      default=gnome;gtk;
      org.freedesktop.impl.portal.Access=gtk;
      org.freedesktop.impl.portal.FileChooser=gtk;
      org.freedesktop.impl.portal.Notification=gtk;
      org.freedesktop.impl.portal.Secret=gnome-keyring;
    '';

    home.packages =
      (with pkgs; [
        cosmic-files
        kdePackages.gwenview
        xdg-desktop-portal-gtk
        kdePackages.polkit-kde-agent-1
      ])
      ++ lib.optional cfg.appleStudioDisplay.enable pkgs.asdbctl;

    xdg.desktopEntries.screen-recording = {
      name = "Screen Recording";
      genericName = "Screen Recorder";
      comment = "Toggle an area screen recording with wl-screenrec";
      exec = scripts.screenRecordToggle;
      icon = "media-record";
      categories = [
        "AudioVideo"
        "Recorder"
      ];
      startupNotify = false;
      terminal = false;
      type = "Application";
    };

    systemd.user.services.xdg-desktop-portal-gnome = {
      Unit = {
        Description = "Portal service (GNOME implementation)";
        After = [ "graphical-session.target" ];
        Requisite = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };

      Service = {
        Type = "dbus";
        BusName = "org.freedesktop.impl.portal.desktop.gnome";
        ExecStart = "${pkgs.xdg-desktop-portal-gnome}/libexec/xdg-desktop-portal-gnome";
      };

      Install.WantedBy = [ "graphical-session.target" ];
    };

    wayland.windowManager.niri = {
      enable = true;
      package = niriPackage;
      checkConfig = true;
      systemd.enable = false;
      portalPackage = null;
      xwaylandSatellitePackage = null;

      settings = {
        spawn-at-startup = [ "kitty" ];

        debug = lib.mkMerge [
          (lib.mkIf (cfg.renderDevice != null) {
            render-drm-device = cfg.renderDevice;
          })
          (lib.mkIf (cfg.ignoreDrmDevice != null) {
            ignore-drm-device = cfg.ignoreDrmDevice;
          })
        ];

        input = {
          keyboard = {
            xkb = {
              layout = "us";
              model = "";
              rules = "";
              variant = "";
            };
            repeat-delay = 600;
            repeat-rate = 25;
            track-layout = "global";
          };
          touchpad = {
            tap = { };
            natural-scroll = { };
            click-method = "clickfinger";
          };
        };

        animations = {
          slowdown = 1.0;
          workspace-switch.spring._props = {
            damping-ratio = 0.8;
            stiffness = 1000;
            epsilon = 0.0001;
          };
          window-open = {
            duration-ms = 200;
            curve = "ease-out-expo";
          };
          window-close = {
            duration-ms = 200;
            curve = "ease-out-expo";
          };
        };

        layout = {
          gaps = 16;
          center-focused-column = "never";
          background-color = style.palette.background;

          struts = {
            left = 0;
            right = 0;
            top = 0;
            bottom = 0;
          };

          preset-column-widths._children = [
            { proportion = 1.0 / 3.0; }
            { proportion = 1.0 / 2.0; }
            { proportion = 2.0 / 3.0; }
          ];

          default-column-width.proportion = 1.0;
          focus-ring = {
            width = 3;
            active-gradient._props = {
              from = style.palette.accent;
              to = style.palette.accentAlt;
              angle = 45;
              relative-to = "workspace-view";
            };
            inactive-color = style.palette.inactive;
          };

          border.off = { };

          shadow = {
            on = { };
            softness = 30;
            spread = 5;
            offset._props = {
              x = 0;
              y = 5;
            };
            draw-behind-window = false;
            color = "#0007";
          };
        };

        xwayland-satellite.path = lib.getExe pkgs.xwayland-satellite;

        cursor = {
          xcursor-theme = "default";
          xcursor-size = 24;
          hide-after-inactive-ms = 3000;
        };

        prefer-no-csd = { };

        screenshot-path = "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png";

        hotkey-overlay.skip-at-startup = { };

        window-rule = {
          geometry-corner-radius = [
            12.0
            12.0
            12.0
            12.0
          ];
          clip-to-geometry = true;
        };

        binds = {
          # "Mod+Return".spawn = [ "kitty" ];
          "Mod+D".spawn = [ (lib.getExe pkgs.fuzzel) ];
          "Super+Alt+L".spawn-sh = [ scripts.lockScreen ];
          # "Mod+B".spawn = [ "zen-beta" ];

          "Mod+Shift+Slash".show-hotkey-overlay = { };
          "Mod+O".toggle-overview = { };
          "Mod+Q".close-window = { };

          # Focus
          "Mod+Left".focus-column-left = { };
          "Mod+Down".focus-workspace-down = { };
          "Mod+Up".focus-workspace-up = { };
          "Mod+Right".focus-column-right = { };

          # Move windows
          "Mod+Ctrl+Left".move-column-left = { };
          "Mod+Ctrl+Down".move-column-to-workspace-down = { };
          "Mod+Ctrl+Up".move-column-to-workspace-up = { };
          "Mod+Ctrl+Right".move-column-right = { };
          "Mod+Ctrl+H".move-column-left = { };
          "Mod+Ctrl+J".move-window-down = { };
          "Mod+Ctrl+K".move-window-up = { };
          "Mod+Ctrl+L".move-column-right = { };

          "Mod+Home".focus-column-first = { };
          "Mod+End".focus-column-last = { };
          "Mod+Ctrl+Home".move-column-to-first = { };
          "Mod+Ctrl+End".move-column-to-last = { };

          # Monitor focus/move
          "Mod+Shift+Left".focus-monitor-left = { };
          "Mod+Shift+Down".focus-monitor-down = { };
          "Mod+Shift+Up".focus-monitor-up = { };
          "Mod+Shift+Right".focus-monitor-right = { };

          "Mod+Shift+Ctrl+Left".move-column-to-monitor-left = { };
          "Mod+Shift+Ctrl+Down".move-column-to-monitor-down = { };
          "Mod+Shift+Ctrl+Up".move-column-to-monitor-up = { };
          "Mod+Shift+Ctrl+Right".move-column-to-monitor-right = { };

          # Scroll bindings
          "Mod+WheelScrollDown" = {
            _props.cooldown-ms = 150;
            focus-workspace-down = { };
          };
          "Mod+WheelScrollUp" = {
            _props.cooldown-ms = 150;
            focus-workspace-up = { };
          };
          "Mod+Ctrl+WheelScrollDown" = {
            _props.cooldown-ms = 150;
            move-column-to-workspace-down = { };
          };
          "Mod+Ctrl+WheelScrollUp" = {
            _props.cooldown-ms = 150;
            move-column-to-workspace-up = { };
          };

          "Mod+WheelScrollRight".focus-column-right = { };
          "Mod+WheelScrollLeft".focus-column-left = { };
          "Mod+Ctrl+WheelScrollRight".move-column-right = { };
          "Mod+Ctrl+WheelScrollLeft".move-column-left = { };
          "Mod+Shift+WheelScrollDown".focus-column-right = { };
          "Mod+Shift+WheelScrollUp".focus-column-left = { };

          # Workspace by index
          "Mod+1".focus-workspace = [ 1 ];
          "Mod+2".focus-workspace = [ 2 ];
          "Mod+3".focus-workspace = [ 3 ];
          "Mod+4".focus-workspace = [ 4 ];
          "Mod+5".focus-workspace = [ 5 ];
          "Mod+6".focus-workspace = [ 6 ];
          "Mod+7".focus-workspace = [ 7 ];
          "Mod+8".focus-workspace = [ 8 ];
          "Mod+9".focus-workspace = [ 9 ];

          # Column management
          "Mod+BracketLeft".consume-or-expel-window-left = { };
          "Mod+BracketRight".consume-or-expel-window-right = { };
          "Mod+Comma".consume-window-into-column = { };
          "Mod+Period".expel-window-from-column = { };

          # Sizing
          "Mod+R".switch-preset-column-width = { };
          "Mod+Shift+R".switch-preset-window-height = { };
          "Mod+Ctrl+R".reset-window-height = { };
          "Mod+F".maximize-column = { };
          "Mod+Shift+F".fullscreen-window = { };
          "Mod+C".center-column = { };
          "Mod+Minus".set-column-width = [ "-10%" ];
          "Mod+Equal".set-column-width = [ "+10%" ];
          "Mod+Shift+Minus".set-window-height = [ "-10%" ];
          "Mod+Shift+Equal".set-window-height = [ "+10%" ];

          # Floating / tabbed
          "Mod+V".toggle-window-floating = { };
          "Mod+Shift+V".switch-focus-between-floating-and-tiling = { };
          "Mod+W".toggle-column-tabbed-display = { };

          # Toggle bar
          "Mod+I".spawn-sh = [ scripts.barToggleVisible ];
          "Mod+M".spawn-sh = [ scripts.notificationsHistoryPicker ];
          "Mod+N".spawn-sh = [ scripts.notificationsToggleDnd ];

          # Clipboard history
          "Mod+Shift+C".spawn-sh = [ scripts.clipboardHistoryPick ];

          # Screenshots
          "Print".screenshot = { };
          "Ctrl+Print".screenshot-screen = { };
          "Alt+Print".screenshot-window = { };
          "Mod+P".screenshot = { };

          # Screenshot with annotation (region select -> satty editor -> save to Pictures)
          "Mod+Shift+S".spawn-sh = [ scripts.screenshotAnnotate ];

          # Volume (allow when locked)
          "XF86AudioRaiseVolume" = {
            _props.allow-when-locked = true;
            spawn-sh = [ scripts.volumeRaise ];
          };
          "XF86AudioLowerVolume" = {
            _props.allow-when-locked = true;
            spawn-sh = [ scripts.volumeLower ];
          };
          "XF86AudioMute" = {
            _props.allow-when-locked = true;
            spawn-sh = [ scripts.volumeMute ];
          };
          "XF86AudioMicMute" = {
            _props.allow-when-locked = true;
            spawn-sh = [ scripts.micMute ];
          };

          # Media (allow when locked)
          "XF86AudioPlay" = {
            _props.allow-when-locked = true;
            spawn-sh = [ scripts.mediaPlayPause ];
          };
          "XF86AudioStop" = {
            _props.allow-when-locked = true;
            spawn-sh = [ scripts.mediaStop ];
          };
          "XF86AudioPrev" = {
            _props.allow-when-locked = true;
            spawn-sh = [ scripts.mediaPrevious ];
          };
          "XF86AudioNext" = {
            _props.allow-when-locked = true;
            spawn-sh = [ scripts.mediaNext ];
          };

          # Brightness (allow when locked)
          "XF86MonBrightnessUp" = {
            _props.allow-when-locked = true;
            spawn-sh = [ scripts.brightnessRaise ];
          };
          "XF86MonBrightnessDown" = {
            _props.allow-when-locked = true;
            spawn-sh = [ scripts.brightnessLower ];
          };

          # Session
          "Mod+Escape" = {
            _props.allow-inhibiting = false;
            toggle-keyboard-shortcuts-inhibit = { };
          };
          "Mod+Shift+E".quit = { };
          "Mod+Shift+P".power-off-monitors = { };
        };
      };
    };
  };
}
