# modules/home-manager/zoom.nix
#
# Zoom Linux client with Wayland/PipeWire screen sharing.
#
# Zoom's native Wayland screen-share path gates on a compositor allow-list
# (GNOME, KDE/Plasma, sway, Hyprland). Unsupported environments such as niri
# need a small compatibility layer:
#
#   1. Build Zoom with `gnomeXdgDesktopPortalSupport = true` so its FHS env
#      bundles xdg-desktop-portal-gnome (the backend niri speaks to via its
#      org.gnome.Mutter.ScreenCast implementation).
#   2. Wrap the launcher to export XDG_CURRENT_DESKTOP=GNOME:<desktop> so
#      Zoom's allow-list check passes while still preserving the actual
#      compositor name in the suffix.
#   3. Route ScreenCast/Screenshot through the GNOME portal and keep GTK as
#      the fallback portal for the rest.
#   4. Seed ~/.config/zoomus.conf with `enableWaylandShare=true` and
#      `xwayland=false` so Zoom actually uses the PipeWire portal path instead
#      of XWayland capture. The file is seeded idempotently via crudini on
#      every HM switch, so Zoom's own writes to the file are preserved.
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.zoom;
  supportedDesktopEnvironments = [
    "gnome"
    "kde"
    "plasma"
    "sway"
    "hyprland"
  ];
  normalizedDesktopEnvironment = lib.toLower cfg.desktopEnvironment;
  needsDesktopPatch = !(builtins.elem normalizedDesktopEnvironment supportedDesktopEnvironments);

  zoomPkg =
    if needsDesktopPatch then
      pkgs.zoom-us.override {
        gnomeXdgDesktopPortalSupport = true;
      }
    else
      pkgs.zoom-us;

  spoofedDesktop = "GNOME:${cfg.desktopEnvironment}";

  wrappedZoom = pkgs.symlinkJoin {
    name = "zoom-us-${zoomPkg.version}-wrapped";
    paths = [ zoomPkg ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      rm -f $out/bin/zoom $out/bin/zoom-us
      makeWrapper ${zoomPkg}/bin/zoom $out/bin/zoom \
        --set XDG_CURRENT_DESKTOP ${lib.escapeShellArg spoofedDesktop}
      ln -s zoom $out/bin/zoom-us
    '';
    inherit (zoomPkg) meta;
  };
  resolvedZoomPackage = if needsDesktopPatch then wrappedZoom else zoomPkg;

  zoomusConfPath = "${config.home.homeDirectory}/.config/zoomus.conf";
  crudini = "${pkgs.crudini}/bin/crudini";
in
{
  options.local.zoom = {
    enable = lib.mkEnableOption "Zoom Linux client with Wayland/PipeWire screen sharing";

    desktopEnvironment = lib.mkOption {
      type = lib.types.str;
      default = "niri";
      description = ''
        Desktop environment or compositor for the current session. Zoom uses
        its native Wayland screen-share path on GNOME, KDE/Plasma, sway, and
        Hyprland; unsupported environments such as niri enable the GNOME
        portal compatibility wrapper automatically.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        home.packages = [ resolvedZoomPackage ];

        # Zoom persists its settings to ~/.config/zoomus.conf on exit, so we
        # cannot manage it as a nix-store symlink. Instead we ensure the two
        # keys needed to reach the PipeWire capture path are present on every
        # HM switch via crudini; any other key Zoom writes is left alone.
        #
        # The final switch ("Screen-capture mode on Wayland: PipeWire Mode")
        # must be set once in Zoom's UI (Settings > Share Screen > Advanced);
        # its on-disk key name is undocumented so we don't seed it here.
        home.activation.seedZoomusConf = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          conf=${lib.escapeShellArg zoomusConfPath}
          run mkdir -p "$(dirname "$conf")"
          [ -e "$conf" ] || run touch "$conf"
          run ${crudini} --set "$conf" General enableWaylandShare true
          run ${crudini} --set "$conf" General xwayland false
        '';
      }

      (lib.mkIf needsDesktopPatch {
        xdg.portal.extraPortals = with pkgs; [
          xdg-desktop-portal-gtk
        ];
        xdg.portal.config.common = {
          default = [
            "gnome"
            "gtk"
          ];
          "org.freedesktop.impl.portal.Access" = [ "gtk" ];
          "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
          "org.freedesktop.impl.portal.Notification" = [ "gtk" ];
          "org.freedesktop.impl.portal.ScreenCast" = [ "gnome" ];
          "org.freedesktop.impl.portal.Screenshot" = [ "gnome" ];
          "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
        };

        systemd.user.services.xdg-desktop-portal-gnome = {
          Unit = {
            Description = "Portal service (GNOME implementation)";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
          };

          Service = {
            Type = "dbus";
            BusName = "org.freedesktop.impl.portal.desktop.gnome";
            ExecStartPre = "${pkgs.runtimeShell} -lc 'until ${pkgs.systemd}/bin/busctl --user status org.gnome.Mutter.ScreenCast >/dev/null 2>&1; do sleep 0.2; done'";
            ExecStart = "${pkgs.xdg-desktop-portal-gnome}/libexec/xdg-desktop-portal-gnome";
            Restart = "on-failure";
            RestartSec = 1;
          };

          Install.WantedBy = [ "graphical-session.target" ];
        };
      })
    ]
  );
}
