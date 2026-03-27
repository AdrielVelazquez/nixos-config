# modules/home-manager/niri/swaync.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.niri;
  palette = cfg.style.palette;
  fontFamily = cfg.style.font.family;
  tooltipCss = import ./tooltip-css.nix { inherit palette; };
  # 0.12.5 steals focus on niri when notifications appear; 0.12.6 fixes it.
  swayncPackage = pkgs.swaynotificationcenter.overrideAttrs (_: {
    version = "0.12.6";
    src = pkgs.fetchFromGitHub {
      owner = "ErikReider";
      repo = "SwayNotificationCenter";
      tag = "v0.12.6";
      hash = "sha256-U5jsH2hSMTNMCtmo+lIXunam4M+B3xxMQU1SM3ZK5X0=";
    };
  });
  swayncClient = lib.getExe' swayncPackage "swaync-client";
in
{
  options.local.niri.swaync.enable = lib.mkEnableOption "SwayNC notification center";

  config = lib.mkIf (cfg.enable && cfg.swaync.enable) {
    services.swaync = {
      enable = true;
      package = swayncPackage;
      settings = {
        positionX = "right";
        positionY = "top";
        "control-center-positionX" = "right";
        "control-center-positionY" = "top";
        "control-center-margin-top" = 128;
        "control-center-margin-bottom" = 128;
        "control-center-margin-right" = 18;
        cssPriority = "user";
        "control-center-width" = 450;
        "fit-to-screen" = true;

        "notification-window-width" = 400;
        "notification-icon-size" = 40;
        "notification-body-image-height" = 500;
        "notification-body-image-width" = 500;
        "notification-inline-replies" = true;
        "notification-2fa-action" = false;

        timeout = 5;
        "timeout-low" = 5;
        "timeout-critical" = 5;

        "keyboard-shortcuts" = false;
        "image-visibility" = "when-available";
        "transition-time" = 200;
        "hide-on-clear" = false;
        "hide-on-action" = false;
        "script-fail-notify" = true;

        widgets = [
          "mpris"
          "dnd"
          "notifications"
        ];

        "widget-config" = {
          dnd = {
            text = "Do not disturb";
          };

          mpris = {
            "image-size" = 100;
            "image-radius" = 10;
            autohide = false;
            blacklist = [ "org.mpris.MediaPlayer2.playerctld" ];
          };
        };
      };

      style = ''
        @define-color center-bg alpha(${palette.background}, 0.72);
        @define-color background ${palette.background};
        @define-color text ${palette.foreground};
        @define-color text-alt ${palette.muted};
        @define-color background-alt alpha(${palette.background}, 0.78);
        @define-color selected alpha(${palette.accent}, 0.35);
        @define-color hover alpha(${palette.accent}, 0.18);
        @define-color urgent ${palette.danger};

        * {
          all: unset;
          color: @text;
          font-family: "${fontFamily}", monospace;
          font-size: 14px;
          font-weight: 700;
          transition: 200ms;
        }

        .notification {
          padding: 0 5px;
          border-radius: 15px;
          border: 2px solid ${palette.inactive};
          color: @text;
        }

        .notification-background {
          background: @center-bg;
          box-shadow: none;
          border-radius: 15px;
          margin: 8px;
        }

        .notification-row .inline-reply-entry {
          padding: 5px 10px;
          background: @background-alt;
          border-radius: 15px;
        }

        .notification-row .inline-reply-button {
          padding: 5px 10px;
          border-radius: 15px;
          background: @hover;
        }

        .notification-row .inline-reply .inline-reply-button:hover {
          background: @selected;
        }

        .notification .notification-content {
          margin: 10px;
        }

        .notification-content .text-box {
          margin: 0 0 0 15px;
        }

        .notification-content .time {
          font-size: 14px;
          font-weight: 800;
          padding: 2px 0;
        }

        .notification .summary {
          font-size: 16px;
          font-weight: 800;
          margin-bottom: 2px;
          padding: 2px 0;
        }

        .notification .body {
          color: @text-alt;
          font-size: 13px;
        }

        .notification.critical {
          border-color: @urgent;
        }

        .notification.low progress,
        .notification.normal progress,
        .notification.critical progress {
          background: @selected;
        }

        .notification-background .close-button {
          margin: 6px;
          padding: 2px;
          border-radius: 6px;
          background: transparent;
        }

        .notification-background .close-button:hover {
          background: @hover;
        }

        .notification > *:last-child > * {
          min-height: 3.2em;
        }

        .notification > *:last-child > * .notification-action {
          background: @hover;
          margin: 0 6px 9px 6px;
          border-radius: 8px;
        }

        .notification > *:last-child > * .notification-action:hover,
        .notification > *:last-child > * .notification-action:active {
          background: @selected;
        }

        .control-center {
          background: @center-bg;
          border-radius: 15px;
          margin: 5px;
          padding: 12px;
        }

        .control-center .notification-background {
          background: @background-alt;
          margin: 7px 0;
        }

        .control-center .notification-background .close-button,
        .notification-group-close-button {
          opacity: 0;
        }

        .notification-group {
          margin: 0 8px;
        }

        .notification-group-headers {
          color: @text;
          font-weight: 800;
        }

        .notification-group-headers > label {
          margin: 0 3px;
          font-size: 16px;
        }

        .notification-group-icon {
          color: @text;
        }

        .notification-group-collapse-button,
        .notification-group-close-all-button {
          background: transparent;
          color: @text;
          margin: 4px;
          padding: 4px;
          border-radius: 6px;
        }

        .notification-group-collapse-button:hover,
        .notification-group-close-all-button:hover {
          background: @hover;
        }

        .widget-dnd {
          padding: 8px 14px;
          margin: 5px 0;
          border-radius: 12px;
          color: @text;
          background: @background-alt;
        }

        .widget-dnd > label {
          font-size: 16px;
        }

        .widget-dnd switch {
          background: @hover;
          border-radius: 8px;
          box-shadow: none;
          padding: 2px;
        }

        .widget-dnd switch slider {
          background: @text;
          border-radius: 8px;
        }

        .widget-dnd switch:hover {
          background: @selected;
        }

        .widget-title {
          color: ${palette.accent};
          font-size: 16px;
          margin: 8px;
        }

        .widget-mpris {
          background: @background-alt;
          border: 2px solid ${palette.inactive};
          border-radius: 15px;
          margin: 5px 0;
          padding: 0 10px;
        }

        .mpris-overlay {
          background: @background-alt;
        }

        .widget-mpris-player {
          background: @background-alt;
          color: @text;
          margin: 0 5px;
          padding: 10px 0 15px;
        }

        .widget-mpris-player .image-button:hover {
          border-radius: 8px;
          background: @hover;
        }

        .widget-mpris-player button {
          padding: 5px;
          margin: 0 2.5px;
        }

        .widget-mpris-player .mpris-overlay > box:last-child {
          background: alpha(@hover, 0.3);
          border-radius: 16px;
          padding: 0 5px;
        }

        .widget-mpris-album-art {
          border-radius: 16px;
          margin: 6px 4px;
        }

        .widget-mpris-title,
        .widget-mpris-subtitle {
          font-weight: 700;
          margin: 0 3px;
        }

        .widget-mpris-title {
          font-size: 19px;
        }

        .widget-mpris-subtitle {
          color: @text-alt;
          font-size: 14px;
        }

        .control-center-list-placeholder {
          color: @text;
        }

        .blank-window {
          background: transparent;
        }

        ${tooltipCss}
      '';
    };

    systemd.user.services.swaync.Service.Environment = lib.mkAfter [
      "GSK_RENDERER=cairo"
      "LIBGL_ALWAYS_SOFTWARE=1"
    ];

    systemd.user.services.swaync.Service.ExecStartPost = lib.mkAfter [
      "${swayncClient} --dnd-on --skip-wait"
    ];
  };
}
