{
  lib,
  config,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.within.kanata;

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

  # Generate a `linux-dev` line for each device in the user's list.
  deviceCfgLines = concatMapStringsSep "\n" (device: "  linux-dev ${device}") cfg.devices;

  # Generate the full kanata configuration file content.
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
  options.within.kanata.enable = mkEnableOption "Enables kanata Settings";

  options.within.kanata.devices = mkOption {
    type = types.listOf types.str;
    default = [ ];
    description = "List of devices that changes the keyboard layout";
    example = [
      "/dev/input/by-id/usb-Razer_Razer_Blade-event-kbd"
    ];
  };

  config = mkIf cfg.enable {
    home.packages = [ pkgs.kanata ];

    systemd.user.services.kanata = {
      Unit = {
        Description = "Kanata keyboard remapper";
      };

      Service = {
        ExecStart = "${pkgs.kanata}/bin/kanata --cfg ${kanataConfigFile}";
        Restart = "always";
        RestartSec = 1;
      };

      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
