{
  lib,
  config,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.within.steam;

  patchDesktop =
    pkg: appName: from: to:
    lib.hiPrio (
      pkgs.runCommand "$patched-desktop-entry-for-${appName}" { } ''
        mkdir -p $out/share/applications
        sed 's#${from}#${to}#g' < ${pkg}/share/applications/${appName}.desktop > $out/share/applications/${appName}.desktop
      ''
    );
  GPUOffloadApp = pkg: desktopName: patchDesktop pkg desktopName "^Exec=" "Exec=nvidia-offload ";
in
{
  options.within.steam.enable = mkEnableOption "Enables Steam Settings";
  # Steam does lot's of system changes, so we need to call this outside of homemanager
  config = mkIf cfg.enable {
    programs.steam = {
      enable = true;
    };

    environment.systemPackages = with pkgs; [
      (GPUOffloadApp steam "steam")
    ];
  };
}
