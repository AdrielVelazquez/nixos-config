{
  lib,
  config,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.within.kanata;
in
{
  options.within.kanata.enable = mkEnableOption "Enables kanata Settings";
  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      kanata
    ];

    services.kanata = {
      enable = true;
      keyboards = {
        internalKeyboard = {
          devices = [
            "/dev/input/by-id/usb-Razer_Razer_Blade-event-kbd"
            "/dev/input/by-id/usb-Razer_Razer_Blade-if01-event-kbd"
          ];
          extraDefCfg = "process-unmapped-keys yes";
          config = ''
            (defsrc
              grv  1    2    3    4    5    6    7    8    9    0    -    =    bspc
              tab  q    w    e    r    t    y    u    i    o    p    [    ]    \
              caps a    s    d    f    g    h    j    k    l    ;    '    ret
              lsft z    x    c    v    b    n    m    ,    .    /    rsft
            )
            ;; The first layer defined is the layer that will be active by default when
            ;; kanata starts up. This layer is the standard QWERTY layout except for the
            ;; backtick/grave key (@grl) which is an alias for a tap-hold key.
            (deflayer qwerty
              grv   1    2    3    4    5    6    7    8    9    0    -    =    bspc
              tab   q    w    f    p    b    j    l    u    y    ;    [    ]    \
              @caps @a  @r    @s   @t   g    m    @n   @e   @i   @o    '    ret
              lsft  z    x    c    d    v    k    h    ,    .    /    rsft
            )
            (defvar
             tap-time 150
             hold-time 280
            )
            (defalias
             caps (tap-hold $tap-time $hold-time esc lctl)
             a (tap-hold $tap-time $hold-time a lalt)
             r (tap-hold $tap-time $hold-time r lmet)
             s (tap-hold $tap-time $hold-time s lctl)
             t (tap-hold $tap-time $hold-time t lsft)
             n (tap-hold $tap-time $hold-time n rsft)
             e (tap-hold $tap-time $hold-time e rctl)
             i (tap-hold $tap-time $hold-time i rmet)
             o (tap-hold $tap-time $hold-time o ralt)
            )
          '';
        };
      };
    };

  };
}
