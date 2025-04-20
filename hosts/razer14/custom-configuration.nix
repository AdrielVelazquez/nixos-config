# Anything additional that should be added in configuration.nix or hardware-configuration.nix should go here instead.customcus
# This allows faster reproducibility when installing nixos from scratch as both those files can be added into this repo
# And just import the custom-configuration.nix

{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:

{

  imports = [
    # Include the results of the hardware scan.
    ./razer-blade-14-2023.nix
    ./../../modules/services/default.nix
    ./../../modules/system/default.nix
    inputs.home-manager.nixosModules.home-manager

  ];
  within.gnome.enable = true;
  within.cuda.enable = true;
  within.ollama.enable = true;
  within.powertop.enable = true;
  within.mullvad.enable = true;
  # within.solaar.enable = true;
  within.steam.enable = true;
  within.docker.enable = true;
  within.docker.users = [ "adriel" ];
  within.kanata.enable = true;
  within.kanata.devices = [
    "/dev/input/by-id/usb-Razer_Razer_Blade-event-kbd"
    "/dev/input/by-id/usb-Razer_Razer_Blade-if01-event-kbd"
  ];
  services.power-profiles-daemon.enable = true;
  services.upower = {
    enable = true;
    percentageLow = 40;
  };

  # Kernel Versions
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelParams = [
    "acpi_osi=Linux"
    "splash"
    "quiet"
  ];
  # boot.blacklistedKernelModules = [
  #   "i2c_hid_acpi"
  # ];
  #
  # Razer touchpad throwr input errors, and this fixes it.
  # boot.kernelPackages = let
  #   customKernel = pkgs.linuxPackages_latest.kernel.override {
  #     extraConfig = ''
  #       CONFIG_I2C_DESIGNWARE_CORE=y
  #       CONFIG_I2C_DESIGNWARE_PLATFORM=y
  #       CONFIG_I2C_DESIGNWARE_PCI=y
  #     '';
  #   };
  # in pkgs.linuxPackagesFor customKernel;

  # Experimental Features
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nix.settings.download-buffer-size = 671088640;
  nixpkgs.config.allowUnfreePredicate = (_: true);
  boot.loader.systemd-boot.configurationLimit = 5;
  # Garbage Collector Setting
  nix.gc.automatic = true;

  nix.gc.dates = "daily";
  nix.gc.options = "--delete-older-than 7d";

  # Enable Bluetooth
  hardware.bluetooth.enable = true;
  hardware.bluetooth.settings = {
    General = {
      Enable = "Source,Sink,Media,Socket";
    };
  };
  # services.blueman.enable = true;
  # Other Hardware options
  hardware.enableAllFirmware = true;
  boot.kernelModules = [ "thunderbolt" ];

  users.users.adriel.packages = lib.mkDefault [
    pkgs.vim
    pkgs.alsa-tools
    pkgs.home-manager
  ];

  # Shell Envs
  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;

  environment.systemPackages = [
    pkgs.gnumake
    pkgs.libgcc
    pkgs.gcc
    pkgs.zig
    pkgs.usbutils
    pkgs.gparted
    pkgs.mesa
    pkgs.nixfmt-rfc-style
    pkgs.alsa-tools
    pkgs.i2c-tools

  ];
  # Removing some gnome stuff
  environment.gnome.excludePackages = with pkgs; [

    gnome-console

  ];
  # NVIDA STUFF
  hardware.graphics = {
    enable = true;
  };

  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = [
    # "amdgpu"
    "nvidia"
  ];
  # This Enables Thunderbolt 4
  services.hardware.bolt.enable = true;

  hardware.nvidia = {

    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    # Enable this if you have graphical corruption issues or application crashes after waking
    # up from sleep. This fixes it by saving the entire VRAM memory to /tmp/ instead
    # of just the bare essentials.
    powerManagement.enable = true;

    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = true;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    # Support is limited to the Turing and later architectures. Full list of
    # supported GPUs is at:
    # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus
    # Only available from driver 515.43.04+
    # Currently alpha-quality/buggy, so false is currently the recommended setting.
    open = false;

    # Enable the Nvidia settings menu,
    # accessible via `nvidia-settings`.
    nvidiaSettings = true;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.beta;
  };
  hardware.nvidia.prime = {
    # Enabling Offload Mode so that on battery performance uses the iGPU instead of the dGPU for most tasks.
    offload.enable = true;
    offload.enableOffloadCmd = true;
    # Make sure to use the correct Bus ID values for your system!
    # Nvidia RaverBlade 14 (2023) bus info: pci@0000:01:00.0
    # Nvidia RazerBlade 14 (2023) bus info: pci@0000:65:00.0
    nvidiaBusId = "PCI:1:0:0";
    amdgpuBusId = "PCI:65:0:0";

  };

  networking.extraHosts = ''
    192.168.4.27 plex-nix
  '';
}
