# hosts/razer14/custom-configuration.nix
# Razer Blade 14 specific customizations
{ config, pkgs, inputs, lib, ... }:

{
  imports = [
    ../../modules/services/default.nix
    ../../modules/system/default.nix
    inputs.home-manager.nixosModules.home-manager
  ];

  # ============================================================================
  # Module Options
  # ============================================================================
  within.cosmic.enable = true;
  within.cuda.enable = true;
  within.powertop.enable = true;
  within.mullvad.enable = true;
  within.steam.enable = true;
  within.docker.enable = true;
  within.docker.users = [ "adriel" ];
  within.kanata.enable = true;
  within.kanata.devices = [
    "/dev/input/by-id/usb-Razer_Razer_Blade-event-kbd"
    "/dev/input/by-id/usb-Razer_Razer_Blade-if01-event-kbd"
  ];

  # ============================================================================
  # Home Manager
  # ============================================================================
  home-manager.useGlobalPkgs = true;

  # ============================================================================
  # Power Management
  # ============================================================================
  services.power-profiles-daemon.enable = true;
  services.upower = {
    enable = true;
    percentageLow = 50;
  };

  # ============================================================================
  # Packages
  # ============================================================================
  nixpkgs.config.allowUnfreePredicate = (_: true);

  users.users.adriel.packages = lib.mkDefault [
    pkgs.vim
    pkgs.alsa-tools
    pkgs.home-manager
  ];

  environment.systemPackages = with pkgs; [
    zig
    alsa-tools
    i2c-tools
    cmake
    python3
  ];

  # ============================================================================
  # NVIDIA Configuration
  # ============================================================================
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    powerManagement.finegrained = true;
    open = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.beta;
  };

  hardware.nvidia.prime = {
    # Bus IDs from: nix shell nixpkgs#pciutils -c lspci -d ::03xx
    # c4:00.0 - NVIDIA GeForce RTX 5060 Max-Q
    # c5:00.0 - AMD Radeon 880M / 890M
    offload.enable = true;
    offload.enableOffloadCmd = true;
    amdgpuBusId = "PCI:197:0:0";
    nvidiaBusId = "PCI:196:0:0";
  };

  # ============================================================================
  # Networking
  # ============================================================================
  networking.extraHosts = ''
    192.168.4.27 plex-nix
  '';

  # ============================================================================
  # Security
  # ============================================================================
  security.sudo.extraConfig = ''
    Defaults env_keep += "SSH_AUTH_SOCK"
  '';
}
