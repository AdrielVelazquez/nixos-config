# users/adriel/default.nix
#
# Personal `adriel` user, razer14 flavor. Adds niri config tied to the
# razer14 hybrid GPU layout. The reusable bits live in ./common.nix.
{ pkgs, ... }:

{
  imports = [
    ./common.nix
  ];

  local.niri = {
    enable = true;
    renderDevice = "/dev/dri/by-path/pci-0000:c5:00.0-render";
    ignoreDrmDevice = "/dev/dri/by-path/pci-0000:c4:00.0-card";
    brightnessDevice = "amdgpu_bl1";
    hasDgpu = true;
  };

  local.web-mime-defaults.fileManager = "org.kde.dolphin.desktop";

  local.zoom.enable = true;

  home.packages = with pkgs; [
    kdePackages.dolphin
    kdePackages.dolphin-plugins
    kdePackages.kio-extras
  ];
}
