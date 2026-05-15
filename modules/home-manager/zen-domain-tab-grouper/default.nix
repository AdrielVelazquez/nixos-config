{
  lib,
  pkgs,
  config,
  ...
}:

let
  cfg = config.local.zen-domain-tab-grouper;
  extensionId = "zen-domain-tab-grouper@adriel.local";
  extensionManifest = builtins.fromJSON (builtins.readFile ./extension/manifest.json);
  extensionVersion = extensionManifest.version;
  extensionPackage =
    pkgs.runCommand "zen-domain-tab-grouper-${extensionVersion}.xpi"
      { nativeBuildInputs = [ pkgs.zip ]; }
      ''
        cd ${./extension}
        zip -r "$out" manifest.json domain.js tabs.js background.js
      '';
in
{
  options.local.zen-domain-tab-grouper = {
    enable = lib.mkEnableOption "local Zen Browser extension that groups tabs by domain";

    installationMode = lib.mkOption {
      type = lib.types.enum [
        "normal_installed"
        "force_installed"
      ];
      default = "normal_installed";
      description = "Firefox enterprise policy installation mode for the local domain tab grouper extension.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.zen-browser.policies = {
      Preferences."xpinstall.signatures.required" = {
        Value = false;
        Status = "locked";
      };

      ExtensionSettings.${extensionId} = {
        install_url = "file://${extensionPackage}";
        installation_mode = cfg.installationMode;
      };
    };
  };
}
