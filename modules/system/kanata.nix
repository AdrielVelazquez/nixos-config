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
             caps a r s t n e i o
            )
            (defvar
             tap-time 150
             hold-time 280
            )
            (defalias
             caps (tap-hold 100 100 esc lctl)
             a (tap-hold $tap-time $hold-time a lalt)
             r (tap-hold $tap-time $hold-time r lmet)
             s (tap-hold $tap-time $hold-time s lctl)
             t (tap-hold $tap-time $hold-time t lsft)
             n (tap-hold $tap-time $hold-time n rsft)
             e (tap-hold $tap-time $hold-time e rctl)
             i (tap-hold $tap-time $hold-time i rmet)
             o (tap-hold $tap-time $hold-time o ralt)
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
