# modules/system/keyd.nix
{ lib, config, ... }:

let
  cfg = config.local.keyd;
in
{
  options.local.keyd.enable = lib.mkEnableOption "Enables keyd keyboard remapper";

  config = lib.mkIf cfg.enable {
    services.keyd = {
      enable = true;
      keyboards.default = {
        ids = [ "1532:029d:bd34c412" ];
        settings = {
          global = {
            overloadt_tap_timeout = 250;
          };

          nav = {
            h = "left";
            j = "down";
            k = "up";
            l = "right";
          };

          main = {
            # Home row mods (Colemak-DH)
            f = "overloadt(shift, t, 300)";
            d = "overloadt(control, s, 300)";
            s = "overloadt(meta, r, 300)";
            a = "overloadt(alt, a, 300)";

            j = "overloadt(shift, n, 300)";
            k = "overloadt(control, e, 300)";
            l = "overloadt(meta, i, 300)";
            semicolon = "overloadt(alt, o, 300)";

            # Colemak-DH layout
            q = "q";
            w = "w";
            e = "f";
            r = "p";
            t = "b";
            y = "j";
            u = "l";
            i = "u";
            o = "y";
            p = ";";
            g = "g";
            h = "m";
            z = "z";
            x = "x";
            c = "c";
            v = "d";
            b = "v";
            n = "k";
            m = "h";
            comma = ",";
            dot = ".";
            slash = "/";

            space = "overload(nav, space)";
            capslock = "overload(control, esc)";
            leftcontrol = "esc";
          };
        };
      };
    };
  };
}
