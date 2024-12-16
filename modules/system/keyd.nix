{
  lib,
  config,
  ...
}:

with lib;

let
  cfg = config.within.keyd;
in
{
  options.within.keyd.enable = mkEnableOption "Enables keyd Settings";
  config = mkIf cfg.enable {
    # services.keyd = {
    #   enable = true;
    #   keyboards = {
    #     default = {
    #       ids = [ "*" ];
    #       settings = {
    #         main = {
    #         };
    #       };
    #     };
    #   };
    # };

    services.keyd = {
      enable = true;
      keyboards = {
        default = {
          ids = [
            "1532:029d:bd34c412"
          ]; # Match all keyboards; adjust as needed for specific devices.
          settings = {
            global = {
              overloadt_tap_timeout = 250;
            };
            main = {
              # Mod alternatives
              # capslock = "overload(escape, backspace)";
              tab = "layer(nav)";

              # Home row mods
              f = "overloadt(shift, t, 300)"; # Shift when held, T when tapped
              d = "overloadt(control, s, 300)"; # Ctrl when held, S when tapped
              s = "overloadt(meta, r, 300)"; # Meta/Cmd when held, R when tapped
              a = "overloadt(alt, a, 300)"; # Alt when held, A when tapped

              j = "overloadt(shift, n, 300)"; # Shift when held, N when tapped
              k = "overloadt(control, e, 300)"; # Ctrl when held, E when tapped
              l = "overloadt(meta, i, 300)"; # Meta/Cmd when held, I when tapped
              semicolon = "overloadt(alt, o, 300)"; # Alt when held, O when tapped

              # Rest of keyboard
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
            };
            nav = {
              n = "left";
              e = "down";
              i = "up";
              o = "right";
            };
          };
        };
      };
    };
  };
}
