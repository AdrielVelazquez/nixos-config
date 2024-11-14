# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, inputs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./razer-blade-14-2023.nix
      ./../../modules/services/default.nix
      ./../../modules/system/default.nix
      inputs.home-manager.nixosModules.home-manager

    ];
  within.cuda.enable = true;
  within.ollama.enable = true;
  within.tlp.enable = true;
  within.mullvad.enable = true;
  within.steam.enable = true;
  within.docker.enable = true;
  within.docker.users = [ "adriel" ];
  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.luks.devices."luks-3d8312c0-3b6e-48f0-9cff-8794af2eb60a".device = "/dev/disk/by-uuid/3d8312c0-3b6e-48f0-9cff-8794af2eb60a";
  # Kernel Versions
  boot.kernelPackages = pkgs.linuxPackages_latest;
  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";
  # networking.nameservers = [ "9.9.9.9#dns.quad9.net" "149.112.112.112#dns.quad9.net" "2620:fe::fe" "2620:fe::9"];

  # services.resolved = {
  #   enable = true;
  #   dnssec = "true";
  #   domains = [ "~." ];
  #   fallbackDns = [ "9.9.9.9#dns.quad9.net" "149.112.112.112#dns.quad9.net" ];
  #   dnsovertls = "true";
  # };

  # Enable networking
  networking.networkmanager.enable = true;

  # Experimental Features
  nix.settings.experimental-features = [ "nix-command" "flakes"];
  boot.loader.systemd-boot.configurationLimit = 5;
  # Garbage Collector Settings
  nix.gc.automatic = true;
  nix.gc.dates = "daily";
  nix.gc.options = "--delete-older-than 7d";
  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Enable the X11 windowing system.
  services.xserver.enable = true;

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
  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.adriel = {
    isNormalUser = true;
    description = "Adriel";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [
    #  thunderbird
    vim
    alsa-tools
    pkgs.home-manager
    ];
  };

  # Home Manager Setup
  #home-manager = {
  #  inherit pkgs
  #  extraSpecialArgs = { inherit inputs; };
  #  users = {
  #      "adriel" = import ./home.nix;
  #  };
  #};

  # Install firefox.
  programs.firefox.enable = true;


  # Shell Envs
  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  git
  wget
  gnumake
  libgcc
  gcc
  zig
  usbutils
  gparted
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # NVIDA STUFF
  hardware.graphics = {
    enable = true;
  };

  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = [ "amdgpu" "nvidia"  ];
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
    package = config.boot.kernelPackages.nvidiaPackages.beta;
  };
  hardware.nvidia.prime = {
        # Enabling Offload Mode so that on battery performance uses the iGPU instead of the dGPU for most tasks.
        # offload.enable = true;
        # offload.enableOffloadCmd = true;
		# Make sure to use the correct Bus ID values for your system!
        # Nvidia RaverBlade 14 (2023) bus info: pci@0000:01:00.0
        # Nvidia RazerBlade 14 (2023) bus info: pci@0000:65:00.0
		nvidiaBusId = "PCI:1:0:0";
        amdgpuBusId = "PCI:65:0:0";

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
    boot.blacklistedKernelModules = [ "nouveau" "nvidia" "nvidia_drm" "nvidia_modeset" ];
  };
};
  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?

}
