# modules/profiles/desktop.nix
# Desktop systems - audio, graphics, bluetooth, printing
{ lib, pkgs, ... }:

{
  imports = [
    ./base.nix
  ];

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
  # Graphics & Hardware
  # ============================================================================
  hardware.graphics.enable = true;
  hardware.bluetooth.enable = lib.mkDefault true;
  hardware.bluetooth.powerOnBoot = false;

  # ============================================================================
  # Services
  # ============================================================================
  services.printing.enable = lib.mkDefault true;

  # ============================================================================
  # Desktop Packages
  # ============================================================================
  environment.systemPackages = with pkgs; [
    # Build tools
    gcc
    libgcc

    # Hardware utilities
    usbutils
    mesa

    # GUI utilities
    gparted
  ];
}
