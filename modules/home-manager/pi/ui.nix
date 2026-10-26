{
  config,
  lib,
  pkgs,
  piLib,
  ...
}:
let
  cfg = config.local.pi.ui;
  json = pkgs.formats.json { };
  root = package: "${package}/${package.packageRoot}";
  terminalTheme = pkgs.callPackage ../../../packages/pi-terminal-theme.nix { };
  neutralEntry = piLib.mkReexport {
    name = "pi-neutral-foreground.ts";
    module = "neutral-foreground";
  };
  opencodeEntry = piLib.mkReexport {
    name = "pi-opencode-ui.ts";
    module = "opencode-ui";
  };
in
{
  options.local.pi.ui = {
    enable = piLib.mkFeatureEnable "the managed Pi visual owner";
    terminalThemes.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    theme = lib.mkOption {
      type = lib.types.str;
      default = "opencode";
    };
    neutralForeground.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    entries = piLib.mkEntriesOption (
      lib.optionalAttrs cfg.enable (
        {
          opencodeUi = "${opencodeEntry}";
        }
        // lib.optionalAttrs cfg.neutralForeground.enable { neutralForeground = "${neutralEntry}"; }
      )
    );
  };
  config = lib.mkIf (config.local.pi.enable && cfg.enable) {
    # shift+tab belongs to role cycling (model-roles.nix); thinking level moves to ctrl+t and the
    # thinking-block toggle that held it moves to alt+t.
    local.pi.keybindings = {
      "app.thinking.cycle" = "ctrl+t";
      "app.thinking.toggle" = "alt+t";
    };
    local.pi.extraSettings = {
      theme = cfg.theme;
      themes = [
        "${../../../dotfiles/pi/themes/opencode.json}"
        "${../../../dotfiles/pi/themes/cyberdream.json}"
      ]
      ++ lib.optional cfg.terminalThemes.enable "${root terminalTheme}/themes";
      quietStartup = "header";
      extensions = lib.mkBefore (
        [ cfg.entries.opencodeUi ]
        ++ lib.optional cfg.neutralForeground.enable cfg.entries.neutralForeground
      );
    };
  };
}
