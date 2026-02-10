{
  pkgs,
  lib,
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

    # ZSA keyboard (Voyager) udev rules
    # NOTE: Manually ensure plugdev group exists and your user is a member:
    #   sudo groupadd plugdev
    #   sudo usermod -aG plugdev $USER
    local.zsa-keyboard.enable = true;

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
    systemd.services.docker = {
      enable = true;
      description = "Docker Application Container Engine";
      documentation = [ "https://docs.docker.com" ];

      # FIX 1: Start on boot (since we removed the socket trigger)
      wantedBy = [ "multi-user.target" ];

      # FIX 2: Explicitly add dependencies to the service's PATH
      # We removed 'containerd' and 'runc' to stop the infinite recursion in your flake.
      # The main 'docker' package should already reference them internally.
      path = [
        pkgs.docker
        pkgs.iptables
        pkgs.kmod # often needed for loading kernel modules
        pkgs.containerd # Commented out to prevent flake recursion
        pkgs.runc # Commented out to prevent flake recursion
      ];

      serviceConfig = {
        Type = "notify";
        # FIX 3: Remove "-H fd://" so it starts as a standalone daemon
        ExecStart = [
          "${pkgs.docker}/bin/dockerd"
        ];
        ExecReload = [
          "${pkgs.coreutils}/bin/kill -s HUP $MAINPID"
        ];

        # Keep your existing limits
        LimitNOFILE = "1048576";
        LimitNPROC = "infinity";
        LimitCORE = "infinity";
        TasksMax = "infinity";
        TimeoutStartSec = 0;
        Restart = "on-failure";
      };
    };
    # mkForce required to override the hardcoded `true` in system-manager's
    # upstream userborn.nix module. See: https://github.com/numtide/system-manager/issues/350
    services.userborn.enable = lib.mkForce false;

    # WARNING: Do not use users.users or users.groups with system-manager on non-NixOS.
    # The NixOS user management module resets /etc/shadow permissions to 000,
    # which breaks non-root authentication (lock screen, chsh, etc.).
    # Manage users/groups imperatively instead (useradd, groupadd, chsh).
  };
}
