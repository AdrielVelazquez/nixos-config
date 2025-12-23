# modules/nixos/common.nix
# Shared configuration for all NixOS hosts
{ lib, pkgs, ... }:

{
  imports = [
    ../services/default.nix
    ../system/default.nix
  ];

  # ============================================================================
  # Nix Settings
  # ============================================================================
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.download-buffer-size = 671088640;
  nix.settings.auto-optimise-store = true;

  # Garbage Collection
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 7d";
  };

  # ============================================================================
  # Boot
  # ============================================================================
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 5;
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

  # ============================================================================
  # Networking
  # ============================================================================
  networking.networkmanager.enable = true;

  # ============================================================================
  # Localization
  # ============================================================================
  time.timeZone = lib.mkDefault "America/New_York";
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
  i18n.extraLocaleSettings = lib.genAttrs [
    "LC_ADDRESS"
    "LC_IDENTIFICATION"
    "LC_MEASUREMENT"
    "LC_MONETARY"
    "LC_NAME"
    "LC_NUMERIC"
    "LC_PAPER"
    "LC_TELEPHONE"
    "LC_TIME"
  ] (_: "en_US.UTF-8");

  # ============================================================================
  # Audio (PipeWire)
  # ============================================================================
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # ============================================================================
  # Hardware
  # ============================================================================
  hardware.bluetooth.enable = lib.mkDefault true;
  hardware.graphics.enable = true;

  # ============================================================================
  # Services
  # ============================================================================
  services.printing.enable = true;

  # ============================================================================
  # Shell
  # ============================================================================
  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;

  # ============================================================================
  # Packages
  # ============================================================================
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    vim
    git
    wget
    gnumake
    gcc
    libgcc
    usbutils
    gparted
    mesa
    nixfmt-rfc-style
    home-manager
  ];
}

