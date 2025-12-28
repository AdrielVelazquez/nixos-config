{
  lib,
  config,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.local.kanata;

  # This logic for generating the config file remains exactly the same.
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

  deviceCfgLines = concatMapStringsSep "\n" (device: "  linux-dev ${device}") cfg.devices;

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
  # --- Options (kept the same for your convenience) ---
  options.local.kanata.enable = mkEnableOption "Enables kanata Settings";

  options.local.kanata.devices = mkOption {
    type = types.listOf types.str;
    default = [ ];
    description = "List of devices that changes the keyboard layout";
    example = [
      "/dev/input/by-id/usb-Razer_Razer_Blade-event-kbd"
    ];
  };

  # --- NixOS System Configuration ---
  config = mkIf cfg.enable {
    # Install kanata system-wide
    environment.systemPackages = [ pkgs.kanata ];

    # Create a system-level systemd service (runs as root)
    systemd.services.kanata = {
      description = "Kanata keyboard remapper";

      # Service settings
      serviceConfig = {
        ExecStart = "${pkgs.kanata}/bin/kanata --cfg ${kanataConfigFile}";
        Restart = "always";
        RestartSec = 1;
      };

      # Start the service when the system is ready for multi-user logins
      wantedBy = [ "multi-user.target" ];
    };
  };
}
