# In your home.nix or a dedicated module

{
  pkgs,
  lib,
  config,
  ...
}:

with lib;

let
  cfg = config.within.shortwave;
in
{

  options.within.shortwave.enable = mkEnableOption "Enables shortwave Settings";
  config = mkIf cfg.enable {
    # 1. Make sure brave is installed through home-manager
    home.packages = [
      pkgs.brave
    ];

    # 2. Define the desktop application entry for the Shortwave PWA
    xdg.desktopEntries."shortwave-pwa" = {
      name = "Shortwave";
      comment = "Shortwave PWA using Brave Browser";

      # The main command to launch the PWA using its specific app-id.
      # Nix automatically finds the correct path to the brave executable.
      exec = "${pkgs.brave}/bin/brave --profile-directory=Default --app-id=lnachpgegbbmnnlgpokibfjlmppeciah \"--app-launch-url-for-shortcuts-menu-item=https://app.shortwave.com/compose?utm_source=pwa_shortcut\"";

      # Brave automatically creates and manages the icon based on the app-id.
      # This name tells the desktop environment which icon to use.
      icon = "brave-lnachpgegbbmnnlgpokibfjlmppeciah-Default";

      terminal = false;
      categories = [
        "Network"
        "WebBrowser"
        "Application"
        "Email"
      ];

      # Use `settings` for keys that aren't direct options, like StartupWMClass.
      # This replaces the old `extraConfig` option.
      settings = {
        StartupWMClass = "crx_lnachpgegbbmnnlgpokibfjlmppeciah";
      };

      # This section creates the right-click "quick actions" for the application icon.
      # The `Exec` lines for actions now have quoted arguments to be compliant.
      actions = {
        "Compose" = {
          name = "Compose";
          exec = "${pkgs.brave}/bin/brave --profile-directory=Default --app-id=lnachpgegbbmnnlgpokibfjlmppeciah \"--app-launch-url-for-shortcuts-menu-item=https://app.shortwave.com/compose?utm_source=pwa_shortcut\"";
        };
        "Inbox" = {
          name = "Inbox";
          exec = "${pkgs.brave}/bin/brave --profile-directory=Default --app-id=lnachpgegbbmnnlgpokibfjlmppeciah \"--app-launch-url-for-shortcuts-menu-item=https://app.shortwave.com/?utm_source=pwa_shortcut\"";
        };
        "Search" = {
          name = "Search";
          exec = "${pkgs.brave}/bin/brave --profile-directory=Default --app-id=lnachpgegbbmnnlgpokibfjlmppeciah \"--app-launch-url-for-shortcuts-menu-item=https://app.shortwave.com/search?utm_source=pwa_shortcut\"";
        };
      };
    };
  };
}
