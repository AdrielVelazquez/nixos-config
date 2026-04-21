# modules/profiles/base.nix
{ lib, pkgs, ... }:

{
  imports = [
    ../services/default.nix
    ../system/default.nix
  ];

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    download-buffer-size = 671088640;
    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://cuda-maintainers.cachix.org"
      "https://niri.cachix.org"
    ];

    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUPT9qbgf2oDZA7A3nU2X8="
      "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
    ];
  };

  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 7d";
  };

  # Deduplicate the store on a timer instead of after every build, so large
  # closures don't stall at the end of `nixos-rebuild`.
  nix.optimise = {
    automatic = true;
    dates = [ "weekly" ];
  };

  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;
  boot.loader.systemd-boot.configurationLimit = lib.mkDefault 10;
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

  networking.networkmanager.enable = lib.mkDefault true;

  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;

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

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    vim
    git
    wget
    gnumake
    nixfmt
    home-manager
  ];
}
