# System customizations - this is where your config goes
# Keeping this separate from configuration.nix means nixos-generate-config
# won't overwrite your customizations
{ pkgs, ... }:

{
  # ============================================================================
  # Module Options (local.* namespace)
  # ============================================================================
  # Enable our custom "hello" module
  local.hello.enable = true;
  local.hello.greeting = "Welcome to NixOS!";

  # ============================================================================
  # Boot
  # ============================================================================
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ============================================================================
  # Networking
  # ============================================================================
  networking.networkmanager.enable = true;

  # ============================================================================
  # Users
  # ============================================================================
  users.users.myuser = {
    isNormalUser = true;
    description = "My User";
    extraGroups = [ "networkmanager" "wheel" ];
  };

  # ============================================================================
  # Packages
  # ============================================================================
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
  ];

  # ============================================================================
  # Nix Settings
  # ============================================================================
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}

