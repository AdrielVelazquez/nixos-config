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
  imports = [ ./ai-kitten-patch-pkgs-system-warning.nix ];

  options.local.ai-kitten = {
    enable = lib.mkEnableOption "ai-kitten Codex CLI integration in kitty";

    model = lib.mkOption {
      type = lib.types.str;
      default = "gpt-5.5";
      description = "Codex model used by ai-kitten.";
    };

    reasoningEffort = lib.mkOption {
      type = lib.types.enum [
        "minimal"
        "low"
        "medium"
        "high"
        "xhigh"
      ];
      default = "xhigh";
      description = "Reasoning effort requested from Codex.";
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
        provider = "codex_cli";
        max_context_lines = 0;
        codex = {
          command = "codex";
          model = cfg.model;
          reasoning_effort = cfg.reasoningEffort;
          sandbox = "read-only";
          approval_policy = "never";
          timeout_seconds = 120;
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
