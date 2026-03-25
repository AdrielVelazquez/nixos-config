# modules/home-manager/niri/swaync.nix
{
  lib,
  config,
  ...
}:

let
  cfg = config.local.niri;
  palette = cfg.style.palette;
  fontFamily = cfg.style.font.family;
  tooltipCss = import ./tooltip-css.nix { inherit palette; };
in
{
  options.local.niri.swaync.enable = lib.mkEnableOption "SwayNC notification center";

  config = lib.mkIf (cfg.enable && cfg.swaync.enable) {
    services.swaync = {
      enable = true;
      style = ''
        * {
          font-family: "${fontFamily}", monospace;
          font-size: 14px;
        }

        .control-center {
          background: alpha(${palette.background}, 0.8);
          border-radius: 12px;
          border: 2px solid ${palette.inactive};
        }

        .notification {
          background: alpha(${palette.background}, 0.7);
          border-radius: 10px;
          box-shadow: 0 0 5px rgba(0,0,0,0.5);
          margin: 4px;
          padding: 8px;
        }

        .notification-content {
          color: ${palette.foreground};
        }

        .close-button {
          background: ${palette.danger};
          color: #11111b;
          border-radius: 4px;
        }

        .close-button:hover {
          background: #e78284;
        }

        .widget-title {
          color: ${palette.accent};
          font-size: 16px;
          margin: 8px;
        }

        .widget-mpris {
          background: alpha(${palette.background}, 0.7);
          border-radius: 10px;
          margin: 8px;
        }

        ${tooltipCss}
      '';
    };
  };
}
