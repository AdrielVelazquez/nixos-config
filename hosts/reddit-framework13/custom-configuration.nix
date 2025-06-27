# Anything additional that should be added in configuration.nix or hardware-configuration.nix should go here instead.customcus
# This allows faster reproducibility when installing nixos from scratch as both those files can be added into this repo
# And just import the custom-configuration.nix

{
  pkgs,
  inputs,
  lib,
  ...
}:

{

  imports = [
    ./../../modules/services/default.nix
    ./../../modules/system/default.nix
    ./../../modules/reddit/default.nix
    inputs.home-manager.nixosModules.home-manager
  ];
  within.cosmic.enable = true;
  # within.solaar.enable = true;
  within.docker.enable = true;
  within.docker.users = [ "adriel" ];
  within.kanata.enable = true;
  within.kanata.devices = [
    "/dev/input/by-path/platform-i8042-serio-0-event-kbd"
  ];
  within.falcon.enable = true;

  within.redshift.enable = true;
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
  programs.git = {
    enable = true;
    config = {
      push.default = "current";
      url."git+ssh@github.snooguts.net:".insteadOf = "https://github.snooguts.net/";
    };
  };
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

  users.users.adriel.packages = lib.mkDefault [
  ];

  security.sudo.enable = true;
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
    pkgs.gh
    pkgs.cmake
    pkgs.slack
    pkgs.infrared
    pkgs.snoologin
    pkgs.snoodev
    pkgs.reddit-lint-py
  ];

  hardware.graphics = {
    enable = true;
  };

  # This Enables Thunderbolt 4
  services.hardware.bolt.enable = true;

  # SSH stuff
  # programs.ssh.startAgent = true;
  services.gnome.gcr-ssh-agent.enable = false;
}
