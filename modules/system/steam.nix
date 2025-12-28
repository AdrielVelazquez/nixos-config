# modules/system/steam.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.steam;

  # Patch desktop entry to use nvidia-offload
  patchDesktop =
    pkg: appName: from: to:
    lib.hiPrio (
      pkgs.runCommand "patched-desktop-entry-for-${appName}" { } ''
        mkdir -p $out/share/applications
        sed 's#${from}#${to}#g' < ${pkg}/share/applications/${appName}.desktop > $out/share/applications/${appName}.desktop
      ''
    );

  GPUOffloadApp = pkg: desktopName: patchDesktop pkg desktopName "^Exec=" "Exec=nvidia-offload ";
in
{
  options.local.steam.enable = lib.mkEnableOption "Enables Steam gaming platform";

  config = lib.mkIf cfg.enable {
    programs.steam.enable = true;

    environment.systemPackages = [
      (GPUOffloadApp pkgs.steam "steam")
    ];
  };
}
