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
    # Include the results of the hardware scan.
    ./../../modules/services/default.nix
    ./../../modules/system/default.nix
    inputs.home-manager.nixosModules.home-manager

  ];
  # within.gnome.enable = true;
  within.cosmic.enable = true;
  # within.solaar.enable = true;
  within.docker.enable = true;
  within.docker.users = [ "adriel" ];
  within.kanata.enable = true;
  # within.kanata.devices = [
  #   "/dev/input/by-id/usb-Razer_Razer_Blade-event-kbd"
  #   "/dev/input/by-id/usb-Razer_Razer_Blade-if01-event-kbd"
  # ];
  services.power-profiles-daemon.enable = true;
  services.upower = {
    enable = true;
    percentageLow = 40;
  };

  # Kernel Versions
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Experimental Features
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

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
  hardware.bluetooth.settings = {
    General = {
      Enable = "Source,Sink,Media,Socket";
    };
  };
  # services.blueman.enable = true;
  # Other Hardware options
  hardware.enableAllFirmware = true;
  boot.kernelModules = [ "thunderbolt" ];

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
  ];
  # Removing some gnome stuff
  # NVIDA STUFF
  hardware.graphics = {
    enable = true;
  };

  # This Enables Thunderbolt 4
  services.hardware.bolt.enable = true;

}
