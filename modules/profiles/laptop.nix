# modules/profiles/laptop.nix
# Laptop systems - desktop + power management + battery optimizations
{ lib, pkgs, ... }:

{
  imports = [
    ./desktop.nix
  ];

  # ============================================================================
  # Power Management
  # ============================================================================
  services.upower.enable = lib.mkDefault true;
  services.power-profiles-daemon.enable = lib.mkDefault true;

  # ============================================================================
  # Laptop-specific Services
  # ============================================================================
  # Firmware updates
  services.fwupd.enable = lib.mkDefault true;

  # SSD health
  services.fstrim.enable = lib.mkDefault true;

  # ============================================================================
  # Laptop Packages
  # ============================================================================
  environment.systemPackages = with pkgs; [
    acpi
    powertop
    pciutils
  ];
}

