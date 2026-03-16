# modules/home-manager/niri/swaync.nix
{
  lib,
  config,
  ...
}:

let
  cfg = config.local.niri;
in
{
  options.local.niri.swaync.enable = lib.mkEnableOption "SwayNC notification center";

  config = lib.mkIf (cfg.enable && cfg.swaync.enable) {
    services.swaync = {
      enable = true;
      style = ''
        * {
          font-family: "Maple Mono NF", monospace;
          font-size: 14px;
        }

        .control-center {
          background: rgba(0, 0, 0, 0.8);
          border-radius: 12px;
          border: 2px solid #383838;
        }

        .notification {
          background: rgba(0, 0, 0, 0.7);
          border-radius: 10px;
          box-shadow: 0 0 5px rgba(0,0,0,0.5);
          margin: 4px;
          padding: 8px;
        }

        .notification-content {
          color: #cdd6f4;
        }

        .close-button {
          background: #f38ba8;
          color: #11111b;
          border-radius: 4px;
        }

        .close-button:hover {
          background: #e78284;
        }

        .widget-title {
          color: #5a9cbf;
          font-size: 16px;
          margin: 8px;
        }

        .widget-mpris {
          background: rgba(0, 0, 0, 0.7);
          border-radius: 10px;
          margin: 8px;
        }
      '';
    };
  };
}
