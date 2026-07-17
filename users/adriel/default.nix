# users/adriel/default.nix
#
# Personal `adriel` user, razer14 flavor. Adds niri config tied to the
# razer14 hybrid GPU layout. The reusable bits live in ./common.nix.
{ ... }:

{
  imports = [
    ./common.nix
    ../../modules/home-manager/opencode-work.nix
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
  local.zoom.enable = true;
  local.opencode.llmPlatform = {
    enable = true;
    defaultModel = "llmplatform/claude-opus-4-8";
  };
  local.noctalia.enable = false;
  local.sops.ageKeyFile = "/home/adriel/.config/sops/age/keys.txt";

  local.zen-browser = {
    aggressiveGpuAcceleration = true;
    forceIntegratedGpu = true;
  };
}
