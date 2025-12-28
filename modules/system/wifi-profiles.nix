# modules/system/wifi-profiles.nix
# Declarative WiFi profiles with SOPS-encrypted passwords
#
# Usage:
#   within.wifi-profiles.cotu.enable = true;
#   within.wifi-profiles.reddit-guest.enable = true;
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.within.wifi-profiles;

  # Predefined network configurations
  knownNetworks = {
    cotu = {
      ssid = "Cotu's Wifi";
      secretName = "wifi_cotu_password";
      passwordEnvVar = "WIFI_COTU_PASSWORD";
      priority = 100;
    };
    reddit-guest = {
      ssid = "Reddit-Guest";
      secretName = "wifi_reddit_guest_password";
      passwordEnvVar = "WIFI_REDDIT_GUEST_PASSWORD";
      priority = 50;
    };
    # Add more networks here as needed
  };

  # Filter to only enabled networks
  enabledNetworks = lib.filterAttrs (name: _: cfg.${name}.enable or false) knownNetworks;

  # Generate module options for each known network
  mkNetworkOption = name: networkCfg: {
    enable = lib.mkEnableOption "WiFi profile for ${networkCfg.ssid}";
  };

in
{
  options.within.wifi-profiles = lib.mapAttrs mkNetworkOption knownNetworks // {
    sopsFile = lib.mkOption {
      type = lib.types.path;
      default = ../../secrets/secrets-enc.yaml;
      description = "Path to SOPS secrets file containing WiFi passwords";
    };

    ageKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/sops/age/keys.txt";
      description = ''
        Path to the age key file for SOPS decryption.
        Default: /var/lib/sops/age/keys.txt (system-level)
        Alternative: /home/<user>/.config/sops/age/keys.txt (user-level, needs root access)
      '';
    };
  };

  config = lib.mkIf (enabledNetworks != { }) {
    # Configure SOPS age key for system-level secrets
    sops.age.keyFile = lib.mkDefault cfg.ageKeyFile;

    # Declare SOPS secrets for each enabled network
    sops.secrets = lib.mapAttrs' (name: network: {
      name = network.secretName;
      value = {
        sopsFile = cfg.sopsFile;
      };
    }) enabledNetworks;

    # Create NetworkManager profiles
    networking.networkmanager.ensureProfiles = {
      # Collect all secret paths as environment files
      environmentFiles = lib.mapAttrsToList
        (name: network: config.sops.secrets.${network.secretName}.path)
        enabledNetworks;

      # Generate profiles for each enabled network
      profiles = lib.mapAttrs' (name: network: {
        name = builtins.replaceStrings [ "'" " " ] [ "" "-" ] network.ssid;
        value = {
          connection = {
            id = network.ssid;
            type = "wifi";
            autoconnect = true;
            autoconnect-priority = network.priority;
          };
          wifi = {
            ssid = network.ssid;
            mode = "infrastructure";
          };
          wifi-security = {
            key-mgmt = "wpa-psk";
            psk = "\$${network.passwordEnvVar}";
          };
           ipv4.method = "auto";
          ipv6.method = "auto";
        };
      }) enabledNetworks;
    };
  };
}
