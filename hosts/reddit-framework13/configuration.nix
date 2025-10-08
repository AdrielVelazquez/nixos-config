{
  pkgs,
  lib,
  reddit,
  ...
}:

{
  config = {
    nixpkgs.hostPlatform = "x86_64-linux";
    nixpkgs.config.allowUnfree = true;

    users.defaultUserShell = pkgs.zsh;

    environment.systemPackages = [
      pkgs.gparted
      pkgs.nixfmt-rfc-style
    ];

  };
}
