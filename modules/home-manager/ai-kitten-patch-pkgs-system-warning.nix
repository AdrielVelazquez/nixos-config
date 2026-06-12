# Temporary copy of the upstream ai-kitten Home Manager module with
# pkgs.system replaced for nixpkgs 26.11pre compatibility.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.ai-kitten;
  pkg = inputs.ai-kitten.packages.${pkgs.stdenv.hostPlatform.system}.ai-kitten;
  jsonFormat = pkgs.formats.json { };
in
{
  options.programs.ai-kitten = {
    enable = lib.mkEnableOption "ai-kitten terminal assistant for Kitty";

    keybinding = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "ctrl+shift+a";
      description = ''
        Keybinding to trigger ai-kitten in Kitty. Set to null if you'd
        rather manage the keybinding yourself.
      '';
    };

    settings = lib.mkOption {
      type = jsonFormat.type;
      default = { };
      example = {
        provider = "codex_cli";
        max_context_lines = 0;
        codex = {
          command = "codex";
          model = "gpt-5.5";
          reasoning_effort = "xhigh";
          sandbox = "read-only";
          approval_policy = "never";
          timeout_seconds = 120;
        };
        panel = {
          orientation = "vertical";
          edge = "right";
          ratio = 0.25;
        };
      };
      description = ''
        Contents of `~/.config/ai-kitten/config.json`. The nested
        provider-specific format, such as `codex = { ... }`, is preferred
        over older flat provider settings.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      pkg
      pkgs.codex
    ];

    xdg.configFile."kitty/ai_kitten.py".source = "${pkg}/share/ai-kitten/ai_kitten.py";
    xdg.configFile."kitty/aikitten".source = "${pkg}/share/ai-kitten/aikitten";

    xdg.configFile."ai-kitten/config.json" = lib.mkIf (cfg.settings != { }) {
      source = jsonFormat.generate "ai-kitten-config.json" cfg.settings;
      force = true;
    };

    programs.kitty.keybindings = lib.mkIf (cfg.keybinding != null) {
      "${cfg.keybinding}" =
        "launch --type=background --cwd=current "
        + "--allow-remote-control "
        + "${pkg}/bin/ai-kitten --launch-panel @active-kitty-window-id";
    };
  };
}
