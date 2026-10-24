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
  ompEntry = pkgs.writeText "pi-omp-theme.ts" ''
    import upstream from "${root cfg.package}/dist/extensions/pi-omp-theme.ts";
    export default upstream;
  '';
  neutralEntry = piLib.mkReexport {
    name = "pi-neutral-foreground.ts";
    module = "neutral-foreground";
  };
  opencodeEntry = piLib.mkReexport {
    name = "pi-opencode-ui.ts";
    module = "opencode-ui";
  };
  omp = cfg.style == "omp";
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
    enable = piLib.mkFeatureEnable "the managed Pi visual owner";
    style = lib.mkOption {
      type = lib.types.enum [
        "opencode"
        "omp"
      ];
      default = "opencode";
      description = ''
        Which visual owner draws the prompt, footer, messages and tool calls. `opencode` is the local
        extension (`dotfiles/pi/extensions/opencode-ui.ts`): a left-bar prompt panel, one-row footer, inline tool
        lines and filled bash/diff blocks. `omp` is the pinned `@nguyenquangthai/pi-omp-theme` composer. Only one
        may own the editor, footer and tool renderers.
      '';
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../packages/pi-omp-theme.nix { };
    };
    terminalThemes.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    theme = lib.mkOption {
      type = lib.types.str;
      default = if omp then "omp-reference" else "opencode";
      defaultText = lib.literalExpression ''"opencode", or "omp-reference" when style is "omp"'';
    };
    settings = lib.mkOption {
      type = json.type;
      default = { };
    };
    neutralForeground.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    entries = piLib.mkEntriesOption (
      lib.optionalAttrs cfg.enable (
        (if omp then { ompTheme = "${ompEntry}"; } else { opencodeUi = "${opencodeEntry}"; })
        // lib.optionalAttrs cfg.neutralForeground.enable { neutralForeground = "${neutralEntry}"; }
      )
    );
  };
  config = lib.mkIf (config.local.pi.enable && cfg.enable) {
    local.pi.extraSettings = {
      theme = cfg.theme;
      themes = [
        "${../../../dotfiles/pi/themes/opencode.json}"
        "${../../../dotfiles/pi/themes/omp-reference.json}"
        "${../../../dotfiles/pi/themes/omp-dark.json}"
      ]
      ++ lib.optional omp "${root cfg.package}/themes"
      ++ lib.optional cfg.terminalThemes.enable "${root terminalTheme}/themes";
      quietStartup = "header";
      extensions = lib.mkBefore (
        [ (if omp then cfg.entries.ompTheme else cfg.entries.opencodeUi) ]
        ++ lib.optional cfg.neutralForeground.enable cfg.entries.neutralForeground
      );
    }
    // lib.optionalAttrs omp {
      piOmpTheme = lib.recursiveUpdate defaults cfg.settings;
    };
  };
}
