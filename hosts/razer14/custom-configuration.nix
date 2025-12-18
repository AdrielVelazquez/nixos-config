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
    ./../../modules/services/default.nix
    ./../../modules/system/default.nix
    inputs.home-manager.nixosModules.home-manager
  ];
  # within.gnome.enable = true;
  within.cosmic.enable = true;
  #within.cuda.enable = true;
  #within.ollama.enable = false;
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
  #within.redshift.enable = true;
  home-manager.useGlobalPkgs = true;
  # within.sops.enable = true;
  services.power-profiles-daemon.enable = true;
  services.upower = {
    enable = true;
    percentageLow = 40;
  };

  # Kernel Versions
  boot.kernelPackages = pkgs.linuxPackages_latest;

  nix.settings.download-buffer-size = 671088640;
  nixpkgs.config.allowUnfreePredicate = (_: true);
  boot.loader.systemd-boot.configurationLimit = 5;
  # Garbage Collector Setting
  nix.gc.automatic = true;

  nix.gc.dates = "daily";
  nix.gc.options = "--delete-older-than 7d";
  nix.settings.auto-optimise-store = true;
  # Enable Bluetooth
  hardware.bluetooth.enable = true;

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
    pkgs.cmake
    pkgs.python3
  ];
  # Removing some gnome stuff
  # NVIDA STUFF
  hardware.graphics = {
    enable = true;
  };

  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = [
    # "amdgpu"
    "nvidia"
  ];

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
    powerManagement.finegrained = false;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    # Support is limited to the Turing and later architectures. Full list of
    # supported GPUs is at:
    # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus
    # Only available from driver 515.43.04+
    # Currently alpha-quality/buggy, so false is currently the recommended setting.
    open = true;

    # Enable the Nvidia settings menu,
    # accessible via `nvidia-settings`.
    nvidiaSettings = true;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.beta;
  };
  hardware.nvidia.prime = {
    # Enabling Offload Mode so that on battery performance uses the iGPU instead of the dGPU for most tasks.
    #offload.enable = true;
    #offload.enableOffloadCmd = true;
    #nvidiaBusId = "PCI:196:0:0";
    #amdgpuBusId = "PCI:197:0:0";
  };

  networking.extraHosts = ''
    192.168.4.27 plex-nix
  '';

  security.sudo.extraConfig = ''
    Defaults env_keep += "SSH_AUTH_SOCK"
  '';
}
