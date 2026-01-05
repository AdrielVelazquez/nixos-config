# modules/home-manager/sops.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.sops;
in
{
  options.local.sops = {
    enable = lib.mkEnableOption "Enables sops-nix for home-manager";

    defaultSopsFile = lib.mkOption {
      type = lib.types.path;
      default = ../../secrets/secrets-enc.yaml;
      description = "Default sops file to use for secrets";
    };

    ageKeyFile = lib.mkOption {
      type = lib.types.str;
      default =
        if pkgs.stdenv.isDarwin then
          "${config.home.homeDirectory}/.config/sops/age/keys.txt"
        else if (builtins.pathExists "/var/lib/sops/age/keys.txt") then
          "/var/lib/sops/age/keys.txt"
        else
          "${config.home.homeDirectory}/.config/sops/age/keys.txt";
      description = ''
        Age key file location.
        - NixOS: /var/lib/sops/age/keys.txt (system-wide)
        - macOS/other: ~/.config/sops/age/keys.txt (user-specific)
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    sops = {
      defaultSopsFile = cfg.defaultSopsFile;

      age = {
        keyFile = cfg.ageKeyFile;
        sshKeyPaths = [ ];
        generateKey = false;
      };
    };

    # Ensure sops age key directory exists
    home.activation.setupSopsAgeKey = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      GREEN='\033[0;32m'
      YELLOW='\033[0;33m'
      NC='\033[0m'

      AGE_KEY_FILE="${cfg.ageKeyFile}"
      AGE_KEY_DIR=$(dirname "$AGE_KEY_FILE")

      $DRY_RUN_CMD mkdir -p "$AGE_KEY_DIR"
      $DRY_RUN_CMD chmod 700 "$AGE_KEY_DIR"

      if [ -f "$AGE_KEY_FILE" ]; then
        $DRY_RUN_CMD chmod 600 "$AGE_KEY_FILE"
        echo -e "''${GREEN}sops age key found at $AGE_KEY_FILE''${NC}"
      else
        echo -e "''${YELLOW}sops age key not found at $AGE_KEY_FILE''${NC}"
        echo "   Please copy your age key to this location."
        echo "   Example: cp /var/lib/sops/age/keys.txt $AGE_KEY_FILE"
      fi
    '';

    home.packages = [
      pkgs.sops

      (pkgs.writeShellScriptBin "sops-check" ''
        #!/usr/bin/env bash

        GREEN='\033[0;32m'
        RED='\033[0;31m'
        YELLOW='\033[0;33m'
        NC='\033[0m'

        echo "sops-nix Configuration Check"
        echo "==============================="
        echo ""

        AGE_KEY_FILE="${cfg.ageKeyFile}"
        SECRETS_DIR="$HOME/.config/sops-nix/secrets"
        SOPS_FILE="${cfg.defaultSopsFile}"

        echo "Age Key File:"
        echo "   Location: $AGE_KEY_FILE"
        if [ -f "$AGE_KEY_FILE" ]; then
          echo -e "   Status: ''${GREEN}Exists''${NC}"
          echo "   Permissions: $(stat -c %a "$AGE_KEY_FILE" 2>/dev/null || stat -f %A "$AGE_KEY_FILE" 2>/dev/null)"
          echo "   Key: $(head -n1 "$AGE_KEY_FILE" | cut -c1-20)..."
        else
          echo -e "   Status: ''${RED}Not found''${NC}"
          echo ""
          echo -e "''${YELLOW}Action needed: Copy your age key to this location''${NC}"

          if [ -f "/var/lib/sops/age/keys.txt" ]; then
            echo "   Found system key, you can copy it:"
            echo "   $ mkdir -p $(dirname "$AGE_KEY_FILE")"
            echo "   $ cp /var/lib/sops/age/keys.txt $AGE_KEY_FILE"
            echo "   $ chmod 600 $AGE_KEY_FILE"
          fi
        fi

        echo ""

        echo "Secrets File:"
        echo "   Location: $SOPS_FILE"
        if [ -f "$SOPS_FILE" ]; then
          echo -e "   Status: ''${GREEN}Exists''${NC}"
          echo "   Size: $(du -h "$SOPS_FILE" | cut -f1)"
        else
          echo -e "   Status: ''${RED}Not found''${NC}"
        fi

        echo ""

        echo "Decrypted Secrets:"
        echo "   Location: $SECRETS_DIR"
        if [ -d "$SECRETS_DIR" ]; then
          echo -e "   Status: ''${GREEN}Exists''${NC}"
          SECRET_COUNT=$(find "$SECRETS_DIR" -type f 2>/dev/null | wc -l)
          echo "   Count: $SECRET_COUNT secrets decrypted"

          if [ $SECRET_COUNT -gt 0 ]; then
            echo ""
            echo "   Available secrets:"
            find "$SECRETS_DIR" -type f -exec basename {} \; 2>/dev/null | sed 's/^/     - /'
          fi
        else
          echo -e "   Status: ''${YELLOW}Not created yet (will be created on rebuild)''${NC}"
        fi

        echo ""

        echo "sops Command:"
        if command -v sops >/dev/null 2>&1; then
          echo -e "   Status: ''${GREEN}Installed''${NC}"
          echo "   Version: $(sops --version 2>&1 | head -n1)"

          echo ""
          echo "Testing decryption..."
          if SOPS_AGE_KEY_FILE="$AGE_KEY_FILE" sops -d "$SOPS_FILE" >/dev/null 2>&1; then
            echo -e "   ''${GREEN}Can successfully decrypt secrets file''${NC}"
          else
            echo -e "   ''${RED}Cannot decrypt secrets file''${NC}"
            echo "   This might mean:"
            echo "     - Age key doesn't match the encrypted file"
            echo "     - Age key file is corrupted"
            echo "     - Secrets file is corrupted"
          fi
        else
          echo -e "   Status: ''${YELLOW}Not found in PATH''${NC}"
          echo "   Install with: nix-shell -p sops"
        fi

        echo ""
        echo "Tips:"
        echo "   - Edit secrets: sops ${cfg.defaultSopsFile}"
        echo "   - View decrypted: sops -d ${cfg.defaultSopsFile}"
        echo "   - Test secret access: cat ~/.config/sops-nix/secrets/<secret-name>"
      '')

      (pkgs.writeShellScriptBin "sops-edit" ''
        #!/usr/bin/env bash
        SOPS_AGE_KEY_FILE="${cfg.ageKeyFile}" \
        sops "${cfg.defaultSopsFile}"
      '')

      (pkgs.writeShellScriptBin "sops-view" ''
        #!/usr/bin/env bash
        SOPS_AGE_KEY_FILE="${cfg.ageKeyFile}" \
        sops -d "${cfg.defaultSopsFile}"
      '')
    ];
  };
}
