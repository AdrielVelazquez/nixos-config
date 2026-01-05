# modules/profiles/desktop.nix
{ lib, pkgs, ... }:

{
  imports = [
    ./base.nix
  ];

  # PipeWire audio
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  hardware.graphics.enable = true;
  hardware.bluetooth.enable = lib.mkDefault true;
  hardware.bluetooth.powerOnBoot = false;

  services.printing.enable = lib.mkDefault true;

  environment.systemPackages = with pkgs; [
    gcc
    libgcc
    usbutils
    mesa
    gparted
  ];
}
