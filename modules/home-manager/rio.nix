# modules/home-manager/rio.nix
{
  lib,
  config,
  ...
}:

let
  cfg = config.local.rio;

  # Same private-use ranges Kitty maps to Symbols Nerd Font Mono.
  symbolMap =
    map
      (range: {
        inherit (range) start end;
        font-family = "Symbols Nerd Font Mono";
      })
      [
        {
          start = "E000";
          end = "E00A";
        }
        {
          start = "EA60";
          end = "EBEB";
        }
        {
          start = "E0A0";
          end = "E0C8";
        }
        {
          start = "E0CA";
          end = "E0CA";
        }
        {
          start = "E0CC";
          end = "E0D7";
        }
        {
          start = "E200";
          end = "E2A9";
        }
        {
          start = "E300";
          end = "E3E3";
        }
        {
          start = "E5FA";
          end = "E6B1";
        }
        {
          start = "E700";
          end = "E7C5";
        }
        {
          start = "ED00";
          end = "EFC1";
        }
        {
          start = "F000";
          end = "F2FF";
        }
        {
          start = "F300";
          end = "F372";
        }
        {
          start = "F400";
          end = "F533";
        }
        {
          start = "F0001";
          end = "F1AF0";
        }
      ];

  # Chords tuios owns; Rio then types them instead of acting on them.
  passthrough = map (chord: chord // { action = "ReceiveChar"; }) [
    {
      key = "t";
      "with" = "control | shift";
    }
    {
      key = "w";
      "with" = "control | shift";
    }
    {
      key = "r";
      "with" = "control | shift";
    }
    {
      key = "d";
      "with" = "control | shift";
    }
    {
      key = "p";
      "with" = "control | shift";
    }
    {
      key = "[";
      "with" = "control | shift";
    }
    {
      key = "]";
      "with" = "control | shift";
    }
    {
      key = "tab";
      "with" = "control";
    }
    {
      key = "tab";
      "with" = "control | shift";
    }
  ];
in
{
  options.local.rio = {
    enable = lib.mkEnableOption "Enables Rio Terminal Settings (trial alongside Kitty)";
  };

  config = lib.mkIf cfg.enable {
    programs.rio = {
      enable = true;

      settings = {
        theme = "monalisa";
        confirm-before-quit = false;
        padding = [ 0 ];

        fonts = {
          family = "Maple Mono NF";
          size = 14;
          features = [
            "-calt"
            "zero"
          ];
          symbol-map = symbolMap;
        };

        # Tabs and splits live in tuios.
        navigation = {
          mode = "Plain";
          use-split = false;
        };

        panel.padding = [ 0 ];

        bindings.keys = passthrough;
      };

      # Kitty's MonaLisa palette on a pure black OLED background.
      themes.monalisa.colors = {
        background = "#000000";
        foreground = "#f6d56a";
        cursor = "#c36c32";
        selection-background = "#f6d56a";
        selection-foreground = "#110b0d";
        black = "#341a0d";
        red = "#9b281b";
        green = "#626132";
        yellow = "#c26e27";
        blue = "#515b5c";
        magenta = "#9b1d29";
        cyan = "#588056";
        white = "#f6d75c";
        light-black = "#874227";
        light-red = "#ff4230";
        light-green = "#b3b163";
        light-yellow = "#ff9565";
        light-blue = "#9eb2b3";
        light-magenta = "#ff5b6a";
        light-cyan = "#89cc8e";
        light-white = "#ffe597";
      };
    };
  };
}
