# modules/profiles/base.nix
# Foundation for all NixOS systems - nix settings, shell, core tools
{ lib, pkgs, ... }:

{
  # Import local.* module definitions (services and system modules)
  imports = [
    ../services/default.nix
    ../system/default.nix
  ];

  # ============================================================================
  # Nix Settings
  # ============================================================================
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    download-buffer-size = 671088640;
    auto-optimise-store = true;
  };

  # Garbage Collection
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 7d";
  };

  # ============================================================================
  # Boot (sensible defaults, can be overridden)
  # ============================================================================
  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;
  boot.loader.systemd-boot.configurationLimit = lib.mkDefault 20;
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

  # ============================================================================
  # Networking
  # ============================================================================
  networking.networkmanager.enable = lib.mkDefault true;

  # ============================================================================
  # Shell
  # ============================================================================
  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;

  # ============================================================================
  # Localization (defaults, override per-host if needed)
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
  # Packages
  # ============================================================================
  nixpkgs.config.allowUnfree = true;

  # Core CLI tools needed on every system
  environment.systemPackages = with pkgs; [
    vim
    git
    wget
    gnumake
    nixfmt-rfc-style
    home-manager
  ];
}
