{
  config,
  lib,
  pkgs,
  ...
}:
let
  fleet = import ../../packages/fleet-official.nix { inherit pkgs; };
in
{
  imports = [
    ../../modules/system/snoocert.nix
    ../../modules/system-manager/apple-studio-display-hbr3.nix
    ../../modules/system/endpoint-agent-limits.nix
  ];

  local.snoocert.enable = true;
  sops = {
    defaultSopsFile = ../../secrets/secrets-enc.yaml;
    useSystemdActivation = true;
    age = {
      keyFile = "/var/lib/sops/age/keys.txt";
      sshKeyPaths = [ ];
      generateKey = false;
    };
    secrets.fleet_enroll_secret = { };
  };

  services.orbit = {
    enable = true;
    fleetUrl = "https://reddit.cloud.fleetdm.com";
    enrollSecretPath = config.sops.secrets.fleet_enroll_secret.path;
    orbitPackage = fleet.orbit;
    hostIdentifier = "uuid";
    enableScripts = true;
    desktop = {
      enable = true;
      package = fleet.desktop;
    };
  };
  systemd.services.orbit = {
    after = [
      "sops-install-secrets.service"
      "snoocert-trust.service"
    ];
    requires = [
      "sops-install-secrets.service"
      "snoocert-trust.service"
    ];
    path = [
      pkgs.bash
      pkgs.zsh
      pkgs.python3
    ];
  };

  services.cloudflare-warp.enable = true;
  systemd.services.cloudflare-warp = {
    after = [ "snoocert-trust.service" ];
    requires = [ "snoocert-trust.service" ];
  };
  local.endpoint-agent-limits.enable = true;

  nix.gc = {
    automatic = true;
    dates = lib.mkForce [ "Sun *-*-* 03:00:00" ];
    options = lib.mkForce "--delete-older-than 14d";
    randomizedDelaySec = "1h";
    persistent = true;
  };
  nix.optimise = {
    automatic = true;
    dates = lib.mkForce [ "Sun *-*-* 05:00:00" ];
    randomizedDelaySec = "1h";
    persistent = true;
  };
  systemd.services.nix-gc.serviceConfig = {
    Nice = 19;
    CPUSchedulingPolicy = "idle";
    IOSchedulingClass = "idle";
  };

  environment.systemPackages = with pkgs; [
    bash
    zsh
    python3
    openssl
    kitty.terminfo
  ];
}
