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
        provider = "cursor";
        max_context_lines = 0;
        cursor = {
          command = "cursor-agent";
          mode = "ask";
          model = "composer-2-fast";
          timeout_seconds = 60;
          api_key_file = "/run/user/1000/secrets/cursor_token";
          stream = true;
        };
        panel = {
          orientation = "vertical";
          edge = "right";
          ratio = 0.25;
        };
      };
      description = ''
        Contents of `~/.config/ai-kitten/config.json`. The nested
        format (cursor = { ... }) is preferred but the flat
        v0.1 format (cursor_api_key_file = "..." etc.) is also
        accepted for backwards compatibility.

        Use `cursor.api_key_file` with sops-nix to keep the secret
        out of the Nix store.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      pkg
      pkgs.codex
      pkgs.cursor-cli
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
