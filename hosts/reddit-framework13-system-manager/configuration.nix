{
  pkgs,
  config,
  ...
}:

{

  imports = [
    ./../../modules/system-manager/default.nix
  ];
  config = {
    local.kanata = {
      enable = true;
      devices = [
        "/dev/input/by-path/platform-i8042-serio-0-event-kbd"
      ];
    };

    # MediaTek WiFi fixes (simple version - no iwd, just config files)
    local.mediatek-wifi.enable = true;

    # System tuning (sysctl, udev rules)
    local.framework-tuning = {
      enable = true;
      ramGB = 64; # Adjust if different
    };

    nixpkgs.hostPlatform = "x86_64-linux";
    nixpkgs.config.allowUnfree = true;

    # Nix configuration (moved from unmanaged /etc/nix/nix.conf)
    nix.settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [
        "root"
        "@wheel"
        "adriel.velazquez"
      ];
    };

    environment.systemPackages = [
      pkgs.zsh
      pkgs.gparted
      pkgs.nixfmt
      pkgs.docker
    ];
    services.userborn.enable = false;

    users.users."adriel.velazquez" = {
      isNormalUser = true;
      home = "/home/adriel.velazquez";
      shell = pkgs.zsh; # Or keep using your system shell
      ignoreShellProgramCheck = true;
    };
  };
}
