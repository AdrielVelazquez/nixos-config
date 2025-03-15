# Anything additional that should be added in configuration.nix or hardware-configuration.nix should go here instead.
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
    ./../../modules/services/default.nix
    ./../../modules/system/default.nix
    inputs.home-manager.nixosModules.home-manager

  ];

  within.mullvad.enable = true;
  within.plex.enable = true;
  witnin.kanata.enable = true;
  # Kernel Versions
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Experimental Features
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Mounting options
  boot.supportedFilesystems = [ "ntfs" ];

  boot.loader.systemd-boot.configurationLimit = 5;
  # Garbage Collector Settings
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
  services.blueman.enable = true;
  # Other Hardware options
  hardware.enableAllFirmware = true;
  boot.kernelModules = [ "thunderbolt" ];
  services.xserver.displayManager.gdm.autoSuspend = false;
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.login1.suspend" ||
            action.id == "org.freedesktop.login1.suspend-multiple-sessions" ||
            action.id == "org.freedesktop.login1.hibernate" ||
            action.id == "org.freedesktop.login1.hibernate-multiple-sessions")
        {
            return polkit.Result.NO;
        }
    });
  '';

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
    pkgs.lshw
    pkgs.home-manager
  ];
  # NVIDA STUFF
  hardware.graphics = {
    enable = true;
  };

  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = [
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
    powerManagement.enable = false;

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
    open = false;

    # Enable the Nvidia settings menu,
    # accessible via `nvidia-settings`.
    nvidiaSettings = true;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };
  hardware.nvidia.prime = {
    # Enabling Offload Mode so that on battery performance uses the iGPU instead of the dGPU for most tasks.
    offload.enable = false;
    offload.enableOffloadCmd = false;
    # Make sure to use the correct Bus ID values for your system!
    # Nvidia RaverBlade 14 (2023) bus info: pci@0000:01:00.0
    # Nvidia RazerBlade 14 (2023) bus info: pci@0000:65:00.0
    nvidiaBusId = "PCI:1:0:0";
    intelBusId = "PCI:0:2:0";

  };
  specialisation = {
    on-the-go.configuration = {
      system.nixos.tags = [ "on-the-go" ];
      boot.extraModprobeConfig = ''
        blacklist nouveau
        options nouveau modeset=0
      '';

      services.udev.extraRules = ''
        # Remove NVIDIA USB xHCI Host Controller devices, if present
        ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c0330", ATTR{power/control}="auto", ATTR{remove}="1"
        # Remove NVIDIA USB Type-C UCSI devices, if present
        ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c8000", ATTR{power/control}="auto", ATTR{remove}="1"
        # Remove NVIDIA Audio devices, if present
        ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x040300", ATTR{power/control}="auto", ATTR{remove}="1"
        # Remove NVIDIA VGA/3D controller devices
        ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x03[0-9]*", ATTR{power/control}="auto", ATTR{remove}="1"
      '';
      boot.blacklistedKernelModules = [
        "nouveau"
        "nvidia"
        "nvidia_drm"
        "nvidia_modeset"
      ];
    };
  };
  # Allow SSHING into this machine
  services.openssh = {
    enable = true;
    ports = [ 22 ];
    settings = {
      # PasswordAuthentication = true;
      AllowUsers = [ "adriel" ]; # Allows all users by default. Can be [ "user1" "user2" ]
      UseDns = true;
      X11Forwarding = false;
      PermitRootLogin = "prohibit-password"; # "yes", "without-password", "prohibit-password", "forced-commands-only", "no"
    };
  };
  users.users."adriel".openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEMABTrdi8D/m+YRUk75jeAQzqe69BHy7P06lN7th7+S adrielvelazquez@gmail.com" # content of authorized_keys file
  ];
  networking.firewall.allowedTCPPorts = [ 22 ];
  services.fail2ban.enable = true;

  # mPrevent this laptop from sleeping
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;

}
