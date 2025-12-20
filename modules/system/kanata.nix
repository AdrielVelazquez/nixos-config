# modules/system/kanata.nix
# System-level Kanata keyboard remapper
{ lib, config, pkgs, ... }:

let
  cfg = config.within.kanata;
in
{
  options.within.kanata = {
    enable = lib.mkEnableOption "Enables Kanata keyboard remapper";

    devices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of input devices for keyboard remapping";
      example = [
        "/dev/input/by-id/usb-Razer_Razer_Blade-event-kbd"
        "/dev/input/by-id/usb-Razer_Razer_Blade-if01-event-kbd"
      ];
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.kanata ];

    services.kanata = {
      enable = true;
      keyboards.internalKeyboard = {
        devices = cfg.devices;
        extraDefCfg = "process-unmapped-keys yes";
        config = ''
          (defsrc
            grv  1    2    3    4    5    6    7    8    9    0    -    =    bspc
            tab  q    w    e    r    t    y    u    i    o    p    [    ]    \
            caps a    s    d    f    g    h    j    k    l    ;    '    ret
            lsft z    x    c    v    b    n    m    ,    .    /    rsft
            lctl lmet lalt          spc             rmet rctl
          )

          (deflayer colemak-dh
            grv   1   2    3    4    5    6    7    8    9    0    -    =    bspc
            tab   q   w    f    p   b    j    l    u    y    ;    [    ]    \
            @caps @a  @r   @s   @t  g    m    @n   @e   @i   @o    '    ret
            lsft  z   x    c    d   v    k    h    ,    .    /    rsft
            lctl  lmet lalt          @spc          rmet rctl
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
           a   (tap-hold $tap-time $hold-time a lalt)
           r   (tap-hold $tap-time $hold-time r lmet)
           s   (tap-hold $tap-time $hold-time s lctl)
           t   (tap-hold $tap-time $hold-time t lsft)
           n   (tap-hold $tap-time $hold-time n rsft)
           e   (tap-hold $tap-time $hold-time e rctl)
           i   (tap-hold $tap-time $hold-time i rmet)
           o   (tap-hold $tap-time $hold-time o ralt)
          )
        '';
      };
    };
  };
}
