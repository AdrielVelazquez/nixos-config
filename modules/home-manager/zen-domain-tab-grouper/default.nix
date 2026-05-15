{
  lib,
  config,
  inputs,
  ...
}:

let
  cfg = config.local.zen-domain-tab-grouper;
in
{
  imports = [
    inputs.zen-group-tabs.homeManagerModules.default
  ];

  options.local.zen-domain-tab-grouper = {
    enable = lib.mkEnableOption "Zen Group Tabs browser extension";

    installationMode = lib.mkOption {
      type = lib.types.enum [
        "normal_installed"
        "force_installed"
      ];
      default = "normal_installed";
      description = "Firefox enterprise policy installation mode for Zen Group Tabs.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.zen-group-tabs = {
      enable = true;
      installationMode = cfg.installationMode;
    };
  };
}
