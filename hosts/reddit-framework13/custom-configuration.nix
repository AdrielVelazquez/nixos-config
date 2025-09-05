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
    inputs.fleet-nix.nixosModules.fleet-nixos
  ];
  within.cosmic.enable = true;
  # within.solaar.enable = true;
  within.docker.enable = true;
  within.docker.users = [ "adriel.velazquez" ];
  within.kanata.enable = true;
  within.kanata.devices = [
    "/dev/input/by-path/platform-i8042-serio-0-event-kbd"
  ];
  # These are reddit specific packages
  within.falcon.enable = true;
  within.duodesktop.enable = true;
  within.fleet.enable = true;
  within.sops.enable = true;

  within.redshift.enable = true;
  # Experimental Features
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.settings.download-buffer-size = 671088640;
  nixpkgs.config.allowUnfreePredicate = (_: true);
  boot.loader.systemd-boot.configurationLimit = 5;
  nix.settings.cores = 0;
  nix.settings.max-jobs = "auto";
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

  users.users."adriel.velazquez".packages = lib.mkDefault [
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
    pkgs.cloudflare-warp
    pkgs.llvm
    pkgs.clang
  ];

  hardware.graphics = {
    enable = true;
  };

  # This Enables Thunderbolt 4
  services.hardware.bolt.enable = true;

  # services.blueman.enable = true;
  # Other Hardware options
  hardware.enableAllFirmware = true;
  boot.kernelModules = [ "thunderbolt" ];

  # SSH stuff
  # programs.ssh.startAgent = true;
  # services.gnome.gcr-ssh-agent.enable = true;
  # xdg.portal.enable = true;
  security.sudo.extraConfig = ''
    Defaults env_keep += "SSH_AUTH_SOCK"
  '';

  # cloudflare-warp
  services.cloudflare-warp.enable = true;
  networking.nameservers = [
    "1.1.1.1"
    "8.8.8.8"
  ];
}
