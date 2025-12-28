# modules/home-manager/kanata.nix
# Kanata keyboard remapper configuration
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.kanata;

  kanataLayersConfig = ''
    (defsrc
      grv  1    2    3    4    5    6    7    8    9    0    -    =    bspc
      tab  q    w    e    r    t    y    u    i    o    p    [    ]    \
      caps a    s    d    f    g    h    j    k    l    ;    '    ret
      lsft z    x    c    v    b    n    m    ,    .    /    rsft
      lctl lmet lalt       spc            rmet rctl
    )

    (deflayer colemak-dh
      grv   1   2   3   4   5   6   7   8   9   0   -   =   bspc
      tab   q   w   f   p   b   j   l   u   y   ;   [   ]   \
      @caps @a  @r  @s  @t  g   m   @n  @e  @i  @o  '   ret
      lsft  z   x   c   d   v   k   h   ,   .   /   rsft
      lctl  lmet lalt       @spc            rmet rctl
    )

    (defvar
      tap-time 300
      hold-time 301
    )

    (deflayermap (nav)
      h left
      j down
      k up
      l right
    )

    (defalias
      caps (tap-hold $tap-time $hold-time esc -)
      spc  (tap-hold 200 200 spc (layer-while-held nav))
      a    (tap-hold $tap-time $hold-time a lalt)
      r    (tap-hold $tap-time $hold-time r lmet)
      s    (tap-hold $tap-time $hold-time s lctl)
      t    (tap-hold $tap-time $hold-time t lsft)
      n    (tap-hold $tap-time $hold-time n rsft)
      e    (tap-hold $tap-time $hold-time e rctl)
      i    (tap-hold $tap-time $hold-time i rmet)
      o    (tap-hold $tap-time $hold-time o ralt)
    )
  '';

  deviceCfgLines = lib.concatMapStringsSep "\n" (device: "  linux-dev ${device}") cfg.devices;

  fullKanataConfig = ''
    (defcfg
      process-unmapped-keys yes
      ${deviceCfgLines}
    )

    ${kanataLayersConfig}
  '';

  kanataConfigFile = pkgs.writeText "kanata.kbd" fullKanataConfig;
in
{
  options.local.kanata = {
    enable = lib.mkEnableOption "Enables Kanata keyboard remapper";

    devices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of input devices for Kanata";
      example = [ "/dev/input/by-id/usb-Razer_Razer_Blade-event-kbd" ];
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.kanata ];

    systemd.user.services.kanata = {
      Unit.Description = "Kanata keyboard remapper";

      Service = {
        ExecStart = "${pkgs.kanata}/bin/kanata --cfg ${kanataConfigFile}";
        Restart = "always";
        RestartSec = 1;
      };

      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
