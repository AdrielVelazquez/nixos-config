{ inputs, lib, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
    ./disko.nix
    ./hardware.nix
    ./work-services.nix
  ];

  networking.hostName = "framework-work";
  services.xserver.xkb.layout = "us";

  local.kanata = {
    enable = true;
    devices = [ "/dev/input/by-path/platform-i8042-serio-0-event-kbd" ];
  };
  local.mediatek-wifi.enable = true;
  networking.networkmanager.wifi.powersave = lib.mkForce false;
  local.niri.enable = true;
  local.apple-studio-display-brightness.enable = true;
  local.apple-studio-display-hbr3.enable = true;
  services.hardware.bolt.enable = true;
  local.zsa-keyboard.enable = true;
  local.keychron-keyboard.enable = true;
  local.docker = {
    enable = true;
    users = [ "adriel" ];
  };

  programs.steam.enable = true;

  users.mutableUsers = true;
  users.users.adriel = {
    isNormalUser = true;
    description = "Adriel Velazquez";
    extraGroups = [
      "networkmanager"
      "wheel"
      "input"
      "tty"
      "plugdev"
    ];
  };
  users.groups.plugdev = { };

  systemd.sleep.settings.Sleep = {
    AllowSuspend = "yes";
    AllowHibernation = "yes";
    AllowSuspendThenHibernate = "yes";
    HibernateDelaySec = "45min";
    HibernateOnACPower = "yes";
    HibernateMode = "shutdown";
  };
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend-then-hibernate";
    HandleLidSwitchExternalPower = "suspend-then-hibernate";
    HandleLidSwitchDocked = "ignore";
  };

  system.stateVersion = "26.05";
}
