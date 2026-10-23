{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.local.pi.ui;
  json = pkgs.formats.json { };
  root = package: "${package}/${package.packageRoot}";
  terminalTheme = pkgs.callPackage ../../packages/pi-terminal-theme.nix { };
  ompEntry = pkgs.writeText "pi-omp-theme.ts" ''
    import upstream from "${root cfg.package}/dist/extensions/pi-omp-theme.ts";
    export default upstream;
  '';
  neutralEntry = pkgs.writeText "pi-neutral-foreground.ts" ''
    export { default } from "${../../dotfiles/pi/extensions/neutral-foreground.ts}";
  '';
  defaults = {
    schemaVersion = 1;
    preset = "omp";
    readonlyTools = false;
    theme = {
      autoApply = "off";
      terminalBackgroundSync = "off";
    };
    statusLine.layout = {
      left = [
        "pi"
        "model_effort"
        "path"
        "git"
        "cost"
      ];
      right = [ "context_pct" ];
      secondary = [ "extension_statuses" ];
    };
    placement = "above";
    editor = {
      style = "boxed";
      frame = "rounded";
    };
    startup.mode = "off";
    compatibility.preferExistingEditor = false;
  };
in
{
  options.local.pi.ui = {
    enable = lib.mkEnableOption "the pinned omp-style Pi visual owner";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../packages/pi-omp-theme.nix { };
    };
    terminalThemes.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    theme = lib.mkOption {
      type = lib.types.str;
      default = "omp-reference";
    };
    settings = lib.mkOption {
      type = json.type;
      default = { };
    };
    neutralForeground.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    entries = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      default = lib.optionalAttrs cfg.enable (
        {
          ompTheme = "${ompEntry}";
        }
        // lib.optionalAttrs cfg.neutralForeground.enable { neutralForeground = "${neutralEntry}"; }
      );
    };
  };
  config = lib.mkIf (config.local.pi.enable && cfg.enable) {
    local.pi.extraSettings = {
      theme = cfg.theme;
      themes = [
        "${../../dotfiles/pi/themes/omp-reference.json}"
        "${../../dotfiles/pi/themes/omp-dark.json}"
        "${root cfg.package}/themes"
      ]
      ++ lib.optional cfg.terminalThemes.enable "${root terminalTheme}/themes";
      quietStartup = "header";
      piOmpTheme = lib.recursiveUpdate defaults cfg.settings;
      extensions = lib.mkBefore (
        [ cfg.entries.ompTheme ] ++ lib.optional cfg.neutralForeground.enable cfg.entries.neutralForeground
      );
    };
  };
}
