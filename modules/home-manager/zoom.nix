# modules/home-manager/zoom.nix
#
# Zoom Linux client wired up for Wayland/PipeWire screen sharing on niri.
#
# Zoom's native Wayland screen-share path gates on a compositor allow-list
# (GNOME, KDE, sway, Hyprland) -- niri is not on it, so out of the box Zoom
# refuses the share dialog with "you need to use gnome, sway, hyprland, or
# x...". This module works around that and routes capture through the real
# portal stack:
#
#   1. Build Zoom with `gnomeXdgDesktopPortalSupport = true` so its FHS env
#      bundles xdg-desktop-portal-gnome (the backend niri speaks to via its
#      org.gnome.Mutter.ScreenCast implementation).
#   2. Wrap the launcher to export XDG_CURRENT_DESKTOP=GNOME:<session> so
#      Zoom's allow-list check passes. GNOME is the right portal for niri,
#      so spoofing GNOME is honest about the backend, not a lie.
#   3. Seed ~/.config/zoomus.conf with `enableWaylandShare=true` and
#      `xwayland=false` (and pipewire screen capture mode) so Zoom actually
#      uses the PipeWire portal path instead of XWayland capture. The file
#      is seeded idempotently via crudini on every HM switch, so Zoom's
#      own writes to the file are preserved.
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.zoom;

  zoomPkg = pkgs.zoom-us.override {
    gnomeXdgDesktopPortalSupport = true;
  };

  spoofedDesktop = "GNOME:${cfg.sessionName}";

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

  zoomusConfPath = "${config.home.homeDirectory}/.config/zoomus.conf";
  crudini = "${pkgs.crudini}/bin/crudini";
in
{
  options.local.zoom = {
    enable = lib.mkEnableOption "Zoom Linux client with Wayland/PipeWire screen sharing on niri";

    sessionName = lib.mkOption {
      type = lib.types.str;
      default = "niri";
      description = ''
        Value appended after `GNOME:` in the spoofed `XDG_CURRENT_DESKTOP`
        Zoom sees. Zoom only offers screen share on GNOME/KDE/sway/Hyprland;
        prefixing with `GNOME` satisfies that check without fully hiding the
        real compositor from child processes.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ wrappedZoom ];

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
  };
}
