{
  pkgs,
  ...
}:

{

  imports = [
    ./../../modules/system-manager/default.nix
  ];
  config = {
    within.kanata = {
      enable = true;
      devices = [
        "/dev/input/by-path/platform-i8042-serio-0-event-kbd"
      ];
    };
    nixpkgs.hostPlatform = "x86_64-linux";
    nixpkgs.config.allowUnfree = true;

    users.defaultUserShell = pkgs.zsh;

    environment.systemPackages = [
      pkgs.gparted
      pkgs.nixfmt-rfc-style
    ];

  };
}
