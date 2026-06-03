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

    local.mediatek-wifi.enable = true;

    local.niri.enable = true;

    local.apple-studio-display-hbr3.enable = true;

    local.zsa-keyboard.enable = true;

    local.docker.enable = true;

    local.endpoint-agent-limits.enable = true;

    local.sops.enable = true;

    local.orbit = {
      enable = true;
      enableScripts = true;
      desktop.enable = true;
    };

    local.falcon-sensor.enable = true;

    local.snoocert = {
      enable = true;
      certPath = "/home/adriel/.config/certs/snoodev-ca.crt";
      distro = "arch";
    };

    nixpkgs.hostPlatform = "x86_64-linux";
    nixpkgs.config.allowUnfree = true;

    nix.enable = true;
    nix.settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [
        "root"
        "@wheel"
        "adriel"
      ];
    };

    environment.systemPackages = [
      pkgs.zsh
      pkgs.gparted
      pkgs.nixfmt
      pkgs.kitty.terminfo
      pkgs.steam
    ];
    environment.etc."systemd/sleep.conf.d/10-suspend-then-hibernate.conf".text = ''
      [Sleep]
      AllowSuspend=yes
      AllowHibernation=yes
      AllowSuspendThenHibernate=yes
      HibernateDelaySec=45min
      HibernateOnACPower=yes
      HibernateMode=shutdown
    '';
    environment.etc."systemd/logind.conf.d/10-lid-switch.conf".text = ''
      [Login]
      HandleLidSwitch=suspend-then-hibernate
      HandleLidSwitchExternalPower=suspend-then-hibernate
      HandleLidSwitchDocked=suspend-then-hibernate
    '';
    environment.etc."modprobe.d/99-amdgpu-resume.conf".text = ''
      # Disable PSR to reduce Framework AMD display/GPU resume failures.
      options amdgpu dcdebugmask=0x10
    '';
    environment.etc."wireplumber/wireplumber.conf.d/51-bluetooth-headphones.conf".text = ''
      # MANAGED BY SYSTEM-MANAGER
      #
      # Bluetooth headset capture forces HSP/HFP mode, which makes headphone
      # playback sound thin. Keep earbuds on A2DP and prefer the Framework's
      # digital microphone for calls.
      wireplumber.settings = {
        bluetooth.autoswitch-to-headset-profile = false
      }

      monitor.alsa.rules = [
        {
          matches = [
            {
              node.name = "alsa_input.pci-0000_c1_00.6.HiFi__Mic1__source"
            }
          ]
          actions = {
            update-props = {
              priority.session = 2500
            }
          }
        }
      ]
    '';
    # mkForce required to override the hardcoded `true` in system-manager's
    # upstream userborn.nix module. See: https://github.com/numtide/system-manager/issues/350
    services.userborn.enable = lib.mkForce false;
  };
}
