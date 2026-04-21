# modules/home-manager/ai-kitten.nix
# Wraps the upstream ai-kitten home-manager module so we only pull
# `inputs.ai-kitten` (a private flake input) into HM closures that opt in.
# Importing this file is what triggers the flake input fetch, so it is
# intentionally NOT in modules/home-manager/default.nix.
{
  lib,
  config,
  inputs,
  ...
}:

let
  cfg = config.local.ai-kitten;
in
{
  imports = [ inputs.ai-kitten.homeManagerModules.default ];

  options.local.ai-kitten = {
    enable = lib.mkEnableOption "ai-kitten cursor integration in kitty";

    cursorCommand = lib.mkOption {
      type = lib.types.str;
      default = "cursor-agent";
      description = ''
        Command to invoke for the cursor provider. Use `cursor-agent` on hosts
        where the dedicated agent CLI is installed, otherwise `cursor`.
      '';
    };

    keybinding = lib.mkOption {
      type = lib.types.str;
      default = "ctrl+shift+a";
      description = "Kitty keybinding to toggle the ai-kitten panel.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.ai-kitten = {
      enable = true;
      keybinding = cfg.keybinding;
      settings = {
        provider = "cursor";
        max_context_lines = 0;
        cursor_api_key_file = config.sops.secrets.cursor_token.path;
        cursor = {
          command = cfg.cursorCommand;
          mode = "ask";
          model = "composer-2-fast";
          timeout_seconds = 60;
          stream = true;
        };
        panel = {
          orientation = "horizontal";
          edge = "bottom";
          ratio = 0.25;
        };
      };
    };
  };
}
