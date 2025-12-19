{
  lib,
  config,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.within.sops;
in
{
  options.within.sops = {
    enable = mkEnableOption "Enables sops-nix for home-manager";
    
    defaultSopsFile = mkOption {
      type = types.path;
      default = ../../modules/system/secrets-enc.yaml;
      description = "Default sops file to use for secrets";
    };
    
    ageKeyFile = mkOption {
      type = types.str;
      default = 
        if pkgs.stdenv.isDarwin 
        then "${config.home.homeDirectory}/.config/sops/age/keys.txt"
        else if (builtins.pathExists "/var/lib/sops/age/keys.txt")
        then "/var/lib/sops/age/keys.txt"
        else "${config.home.homeDirectory}/.config/sops/age/keys.txt";
      description = ''
        Age key file location. 
        - NixOS: /var/lib/sops/age/keys.txt (system-wide)
        - macOS/other: ~/.config/sops/age/keys.txt (user-specific)
      '';
    };
  };

  config = mkIf cfg.enable {
    # Configure sops-nix for home-manager
    sops = {
      # Default sops file for all secrets
      defaultSopsFile = cfg.defaultSopsFile;
      
      # Age key configuration
      age = {
        keyFile = cfg.ageKeyFile;
        # Don't try to use SSH keys (we're managing SSH keys WITH sops)
        sshKeyPaths = [ ];
        # Generate a new key if one doesn't exist
        generateKey = false;
      };
      
      # Secrets will be decrypted to ~/.config/sops-nix/secrets/
      # This works on all systems (NixOS, macOS, standalone home-manager)
    };

    # Ensure sops age key directory exists
    home.activation.setupSopsAgeKey = lib.hm.dag.entryAfter ["writeBoundary"] ''
      AGE_KEY_FILE="${cfg.ageKeyFile}"
      AGE_KEY_DIR=$(dirname "$AGE_KEY_FILE")
      
      $DRY_RUN_CMD mkdir -p "$AGE_KEY_DIR"
      $DRY_RUN_CMD chmod 700 "$AGE_KEY_DIR"
      
      if [ -f "$AGE_KEY_FILE" ]; then
        $DRY_RUN_CMD chmod 600 "$AGE_KEY_FILE"
        echo "✅ sops age key found at $AGE_KEY_FILE"
      else
        echo "⚠️  sops age key not found at $AGE_KEY_FILE"
        echo "   Please copy your age key to this location."
        echo "   Example: cp /var/lib/sops/age/keys.txt $AGE_KEY_FILE"
      fi
    '';

    # Helper scripts and sops package
    home.packages = [
      pkgs.sops
      (pkgs.writeShellScriptBin "sops-check" ''
        #!/usr/bin/env bash
        
        echo "🔐 sops-nix Configuration Check"
        echo "==============================="
        echo ""
        
        AGE_KEY_FILE="${cfg.ageKeyFile}"
        SECRETS_DIR="$HOME/.config/sops-nix/secrets"
        SOPS_FILE="${cfg.defaultSopsFile}"
        
        # Check age key
        echo "📁 Age Key File:"
        echo "   Location: $AGE_KEY_FILE"
        if [ -f "$AGE_KEY_FILE" ]; then
          echo "   Status: ✅ Exists"
          echo "   Permissions: $(stat -c %a "$AGE_KEY_FILE" 2>/dev/null || stat -f %A "$AGE_KEY_FILE" 2>/dev/null)"
          echo "   Key: $(head -n1 "$AGE_KEY_FILE" | cut -c1-20)..."
        else
          echo "   Status: ❌ Not found"
          echo ""
          echo "⚠️  Action needed: Copy your age key to this location"
          
          if [ -f "/var/lib/sops/age/keys.txt" ]; then
            echo "   Found system key, you can copy it:"
            echo "   $ mkdir -p $(dirname "$AGE_KEY_FILE")"
            echo "   $ cp /var/lib/sops/age/keys.txt $AGE_KEY_FILE"
            echo "   $ chmod 600 $AGE_KEY_FILE"
          fi
        fi
        
        echo ""
        
        # Check sops file
        echo "📄 Secrets File:"
        echo "   Location: $SOPS_FILE"
        if [ -f "$SOPS_FILE" ]; then
          echo "   Status: ✅ Exists"
          echo "   Size: $(du -h "$SOPS_FILE" | cut -f1)"
        else
          echo "   Status: ❌ Not found"
        fi
        
        echo ""
        
        # Check decrypted secrets
        echo "🔓 Decrypted Secrets:"
        echo "   Location: $SECRETS_DIR"
        if [ -d "$SECRETS_DIR" ]; then
          echo "   Status: ✅ Exists"
          SECRET_COUNT=$(find "$SECRETS_DIR" -type f 2>/dev/null | wc -l)
          echo "   Count: $SECRET_COUNT secrets decrypted"
          
          if [ $SECRET_COUNT -gt 0 ]; then
            echo ""
            echo "   Available secrets:"
            find "$SECRETS_DIR" -type f -exec basename {} \; 2>/dev/null | sed 's/^/     - /'
          fi
        else
          echo "   Status: ⚠️  Not created yet (will be created on rebuild)"
        fi
        
        echo ""
        
        # Check if sops command is available
        echo "🛠️  sops Command:"
        if command -v sops >/dev/null 2>&1; then
          echo "   Status: ✅ Installed"
          echo "   Version: $(sops --version 2>&1 | head -n1)"
          
          # Try to decrypt the sops file
          echo ""
          echo "🔓 Testing decryption..."
          if SOPS_AGE_KEY_FILE="$AGE_KEY_FILE" sops -d "$SOPS_FILE" >/dev/null 2>&1; then
            echo "   ✅ Can successfully decrypt secrets file"
          else
            echo "   ❌ Cannot decrypt secrets file"
            echo "   This might mean:"
            echo "     - Age key doesn't match the encrypted file"
            echo "     - Age key file is corrupted"
            echo "     - Secrets file is corrupted"
          fi
        else
          echo "   Status: ⚠️  Not found in PATH"
          echo "   Install with: nix-shell -p sops"
        fi
        
        echo ""
        echo "💡 Tips:"
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

