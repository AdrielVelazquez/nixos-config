{
  lib,
  config,
  ...
}:

with lib;

let
  cfg = config.within.kanata;
in
{
  options.within.kanata.enable = mkEnableOption "Enables kanata Settings";
  config = mkIf cfg.enable {
    services.kanata = {
      enable = true;
      keyboards = {
        internalKeyboard = {
          devices = [
            "/devices/pci0000:00/0000:00:08.1/0000:65:00.3/usb1/1-4/1-4:1.1/0003:1532:029D.0002/input/input1"
          ];
          extraDefCfg = "process-unmapped-keys yes";
          config = ''
            (defsrc
             caps a r s t n e i o
            )
            (defvar
             tap-time 150
             hold-time 280
            )
            (defalias
             caps (tap-hold 100 100 esc lctl)
             a (tap-hold $tap-time $hold-time a lalt)
             r (tap-hold $tap-time $hold-time s lmet)
             s (tap-hold $tap-time $hold-time d lctl)
             t (tap-hold $tap-time $hold-time f lsft)
             n (tap-hold $tap-time $hold-time j rsft)
             e (tap-hold $tap-time $hold-time k rctl)
             i (tap-hold $tap-time $hold-time l rmet)
             o (tap-hold $tap-time $hold-time ; ralt)
            )

            (deflayer base
             @caps @a  @r  @s  @t  @n  @e  @i  @o
            )
          '';
        };
      };
    };

  };
}
