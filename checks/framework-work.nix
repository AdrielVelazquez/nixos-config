{
  lib,
  pkgs,
  nixosConfigurations,
  homeConfigurations,
}:
assert lib.assertMsg (nixosConfigurations ? framework-work) "framework-work NixOS host is missing";
let
  host = nixosConfigurations.framework-work.config;
  home = host.home-manager.users.adriel;
  cachy = homeConfigurations.cachyos-framework13.config;
  orbit = host.systemd.services.orbit;
  disk = host.disko.devices;
  check = condition: message: lib.assertMsg condition message;
in
assert check (
  home.home.username == "adriel" && home.home.homeDirectory == "/home/adriel"
) "work login must remain adriel";
assert check (
  !home.local.niri.useSystemHyprlock && cachy.local.niri.useSystemHyprlock
) "NixOS must not use CachyOS's native locker path";
assert check (
  home.local.pi.modelRoles.roles == cachy.local.pi.modelRoles.roles
  && home.local.snoocert.enable
  && home.local.zoom.enable
) "both Framework hosts must share work preferences";
assert check (
  host.programs.niri.enable && host.services.greetd.enable && host.security.pam.services ? hyprlock
) "NixOS must own desktop login and locker PAM";
assert check (
  disk.disk.main.content.partitions.root.content.type == "luks"
  && disk.disk.main.content.partitions.root.content.content.type == "lvm_pv"
) "root and swap must share persistent LUKS encryption";
assert check (
  disk.lvm_vg.framework.lvs.swap.size == "80G" && disk.lvm_vg.framework.lvs.swap.content.resumeDevice
) "disk swap must support hibernation";
assert check (
  host.boot.resumeDevice == "/dev/framework/swap"
  && lib.any (
    swap: swap.device == "/dev/framework/swap" && !swap.randomEncryption.enable
  ) host.swapDevices
) "resume must use persistent disk-backed swap";
assert check (
  host.boot.initrd.luks.devices ? cryptframework
) "systemd initrd must unlock Framework storage";
assert check (
  host.services.orbit.enable
  && host.services.orbit.enableScripts
  && host.services.orbit.desktop.enable
  && lib.versionAtLeast host.services.orbit.orbitPackage.version "1.63.0"
) "Fleet must use official NixOS-capable agents";
assert check (
  orbit.serviceConfig.LoadCredential == [ "enroll-secret:/run/secrets/fleet_enroll_secret" ]
  && orbit.environment.ORBIT_DISABLE_UPDATES == "true"
) "Fleet credentials must stay outside the store and updates declarative";
assert check (
  host.services.cloudflare-warp.enable
  && host.virtualisation.docker.enable
  && builtins.elem "docker" host.users.users.adriel.extraGroups
) "work networking and containers must be enabled";
assert check (
  host.local.kanata.enable
  && host.local.apple-studio-display-hbr3.enable
  && host.services.hardware.bolt.enable
) "Framework keyboard and display integration must survive migration";
assert check (
  host.nix.gc.automatic
  && host.nix.gc.dates == [ "Sun *-*-* 03:00:00" ]
  && host.nix.gc.options == "--delete-older-than 14d"
  && host.nix.optimise.dates == [ "Sun *-*-* 05:00:00" ]
  && host.systemd.services.nix-gc.serviceConfig.CPUSchedulingPolicy == "idle"
  && host.systemd.timers.nix-gc.timerConfig.Persistent
) "Framework must have one bounded maintenance owner";
assert check (
  host.local.snoocert.enable
  && host.environment.etc."ssl/certs/ca-certificates.crt".source == "/run/snoocert/ca-bundle.crt"
  && !host.security.pki.installCACerts
  && host.sops.secrets.snoocert.path == "/run/secrets/snoocert"
) "corporate trust must be assembled only at runtime";
assert check (
  !(host.systemd.services ? falcon-sensor) && !(host.systemd.services ? duo-desktop)
) "resource drop-ins must not impersonate installed endpoint agents";
assert check (
  host.programs.steam.enable
  && host.hardware.steam-hardware.enable
  && !(lib.any (package: lib.getName package == "steam") home.home.packages)
) "native Steam integration must own the system runtime, not a competing Home Manager package";
pkgs.runCommand "framework-work-contract" { } ''
  touch "$out"
''
