# modules/home-manager/web-mime-defaults.nix
# Default browser/PDF mime associations. Same set was duplicated across
# users/adriel and users/adriel-cachyos; this consolidates it.
{
  lib,
  config,
  ...
}:

let
  cfg = config.local.web-mime-defaults;
in
{
  options.local.web-mime-defaults = {
    enable = lib.mkEnableOption "default web + PDF mime associations";

    browser = lib.mkOption {
      type = lib.types.str;
      default = "zen-beta.desktop";
      description = "Desktop file id for the default browser.";
    };

    pdf = lib.mkOption {
      type = lib.types.str;
      default = "okularApplication_pdf.desktop";
      description = "Desktop file id for the default PDF viewer.";
    };
  };

  config = lib.mkIf cfg.enable (
    let
      assoc = {
        "x-scheme-handler/http" = [ cfg.browser ];
        "x-scheme-handler/https" = [ cfg.browser ];
        "x-scheme-handler/chrome" = [ cfg.browser ];
        "text/html" = [ cfg.browser ];
        "application/x-extension-htm" = [ cfg.browser ];
        "application/x-extension-html" = [ cfg.browser ];
        "application/x-extension-shtml" = [ cfg.browser ];
        "application/xhtml+xml" = [ cfg.browser ];
        "application/x-extension-xhtml" = [ cfg.browser ];
        "application/x-extension-xht" = [ cfg.browser ];
        "application/pdf" = [ cfg.pdf ];
      };
    in
    {
      xdg.mimeApps = {
        enable = true;
        associations.added = assoc;
        defaultApplications = assoc;
      };
      # Force these because some apps drop their own mimeapps.list during
      # activation; we want home-manager to win.
      xdg.configFile."mimeapps.list".force = true;
      xdg.dataFile."applications/mimeapps.list".force = true;
    }
  );
}
