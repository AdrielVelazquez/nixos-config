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

  # Printing with Brother support
  services.printing = {
    enable = lib.mkDefault true;
    drivers = with pkgs; [
      brlaser # Open-source Brother laser driver
      brgenml1lpr # Generic Brother driver
      brgenml1cupswrapper
    ];
  };

  # Network printer discovery (mDNS/DNS-SD)
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  environment.systemPackages = with pkgs; [
    gcc
    libgcc
    usbutils
    mesa
    gparted
  ];
}
