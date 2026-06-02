# users/adriel/default.nix
#
# Personal `adriel` user, razer14 flavor. Adds niri config tied to the
# razer14 hybrid GPU layout. The reusable bits live in ./common.nix.
{ ... }:

{
  imports = [
    ./common.nix
  ];

  local.niri = {
    enable = true;
    renderDevice = "/dev/dri/by-path/pci-0000:c5:00.0-render";
    ignoreDrmDevice = "/dev/dri/by-path/pci-0000:c4:00.0-card";
    brightnessDevice = "amdgpu_bl1";
    dgpuPciPath = "/sys/bus/pci/devices/0000:c4:00.0";
    services.internalDisplayAutoOff = {
      enable = true;
      output = "eDP-1";
      ignoredOutputDescriptions = [ "Unknown Unknown Unknown" ];
    };
  };
  programs.niri.settings.outputs = {
    "eDP-1".scale = 1.1;
    "Apple Computer Inc StudioDisplay 0x92E55162".scale = 1.0;
    "DP-8".enable = false;
  };

  local.zoom.enable = true;
  local.noctalia.enable = false;

  local.zen-browser = {
    aggressiveGpuAcceleration = true;
    forceIntegratedGpu = true;
  };
}
