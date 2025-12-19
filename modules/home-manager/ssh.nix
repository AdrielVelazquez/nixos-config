{
  lib,
  config,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.within.ssh;
in
{
  options.within.ssh = {
    enable = mkEnableOption "Enables SSH with sops-encrypted keys";
    
    enableGitHubKeys = mkOption {
      type = types.bool;
      default = true;
      description = "Enable GitHub SSH configuration";
    };
    
    enableRedditKeys = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Reddit internal GitHub SSH configuration";
    };
    
    additionalHosts = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          hostname = mkOption {
            type = types.str;
            description = "SSH hostname";
          };
          user = mkOption {
            type = types.str;
            default = "git";
            description = "SSH user";
          };
          identityFile = mkOption {
            type = types.str;
            default = "~/.ssh/id_ed25519";
            description = "Path to SSH identity file";
          };
        };
      });
      default = {};
      description = "Additional SSH host configurations";
    };
  };

  config = mkIf cfg.enable {
    # Define sops secrets for SSH keys
    # Note: sops-nix will only try to decrypt these if they exist in the secrets file
    sops.secrets.ssh_private_key_ed25519 = {
      path = "${config.home.homeDirectory}/.ssh/id_ed25519";
    };
    
    sops.secrets.ssh_pub_key_ed25519 = {
      path = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
    };

    # Configure SSH
    programs.ssh = {
      enable = true;
      
      # Explicitly disable default config as per deprecation warning
      enableDefaultConfig = false;
      
      matchBlocks = mkMerge [
        # Default configuration for all hosts
        {
          "*" = {
            addKeysToAgent = "yes";
            extraOptions = {
              ServerAliveInterval = "60";
              ServerAliveCountMax = "3";
              ControlMaster = "auto";
              ControlPath = "~/.ssh/sockets/%r@%h:%p";
              ControlPersist = "600";
            };
          };
        }
        # GitHub.com configuration
        (mkIf cfg.enableGitHubKeys {
          "github.com" = {
            hostname = "github.com";
            user = "git";
            identityFile = "~/.ssh/id_ed25519";
            extraOptions = {
              AddKeysToAgent = "yes";
            };
          };
        })
        
        # Reddit internal GitHub
        (mkIf cfg.enableRedditKeys {
          "github.snooguts.net" = {
            hostname = "github.snooguts.net";
            user = "git";
            identityFile = "~/.ssh/id_ed25519";
            extraOptions = {
              AddKeysToAgent = "yes";
            };
          };
        })
        
        # Additional user-defined hosts
        (mapAttrs (name: host: {
          hostname = host.hostname;
          user = host.user;
          identityFile = host.identityFile;
        }) cfg.additionalHosts)
      ];
    };

    # Ensure SSH directory and socket directory exist with correct permissions
    home.activation.setupSshDirs = lib.hm.dag.entryAfter ["writeBoundary"] ''
      $DRY_RUN_CMD mkdir -p $HOME/.ssh
      $DRY_RUN_CMD chmod 700 $HOME/.ssh
      $DRY_RUN_CMD mkdir -p $HOME/.ssh/sockets
      $DRY_RUN_CMD chmod 700 $HOME/.ssh/sockets
    '';

    # Add GitHub hosts to known_hosts (optional, won't overwrite existing)
    # Users can manually add these if needed:
    # ssh-keyscan github.com >> ~/.ssh/known_hosts

    # Helper script to test SSH connections
    home.packages = [
      (pkgs.writeShellScriptBin "ssh-test-keys" ''
        #!/usr/bin/env bash
        
        echo "🔑 SSH Key Configuration Test"
        echo "=============================="
        echo ""
        
        # Check if keys exist
        echo "📁 Checking SSH key files..."
        if [ -f "$HOME/.ssh/id_ed25519" ]; then
          echo "  ✅ id_ed25519 exists"
          echo "     Permissions: $(stat -c %a "$HOME/.ssh/id_ed25519" 2>/dev/null || stat -f %A "$HOME/.ssh/id_ed25519" 2>/dev/null)"
        else
          echo "  ❌ id_ed25519 missing"
        fi
        
        if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
          echo "  ✅ id_ed25519.pub exists"
          echo "     $(head -n1 "$HOME/.ssh/id_ed25519.pub" | cut -d' ' -f1,2 | cut -c1-60)..."
        else
          echo "  ❌ id_ed25519.pub missing"
        fi
        
        echo ""
        echo "🔍 Testing SSH connections..."
        echo ""
        
        # Test GitHub
        echo "Testing github.com..."
        if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
          echo "  ✅ GitHub authentication successful"
        else
          echo "  ⚠️  GitHub authentication response:"
          ssh -T git@github.com 2>&1 | head -n 2 | sed 's/^/     /'
        fi
        
        echo ""
        
        # Test Reddit GitHub if configured
        if grep -q "github.snooguts.net" "$HOME/.ssh/config" 2>/dev/null; then
          echo "Testing github.snooguts.net..."
          if timeout 5 ssh -T git@github.snooguts.net 2>&1 | grep -q "successfully authenticated"; then
            echo "  ✅ Reddit GitHub authentication successful"
          else
            echo "  ⚠️  Reddit GitHub authentication response:"
            timeout 5 ssh -T git@github.snooguts.net 2>&1 | head -n 2 | sed 's/^/     /' || echo "     (timeout or connection issue)"
          fi
        fi
        
        echo ""
        echo "🎯 SSH Configuration:"
        echo "   Config file: $HOME/.ssh/config"
        echo "   Socket dir: $HOME/.ssh/sockets"
        echo ""
        echo "💡 To view your public key:"
        echo "   cat ~/.ssh/id_ed25519.pub"
      '')
      
      (pkgs.writeShellScriptBin "ssh-copy-public-key" ''
        #!/usr/bin/env bash
        
        if [ ! -f "$HOME/.ssh/id_ed25519.pub" ]; then
          echo "❌ Public key not found at ~/.ssh/id_ed25519.pub"
          exit 1
        fi
        
        echo "📋 Your SSH public key:"
        echo ""
        cat "$HOME/.ssh/id_ed25519.pub"
        echo ""
        
        if command -v wl-copy >/dev/null 2>&1; then
          cat "$HOME/.ssh/id_ed25519.pub" | wl-copy
          echo "✅ Copied to clipboard (Wayland)"
        elif command -v xclip >/dev/null 2>&1; then
          cat "$HOME/.ssh/id_ed25519.pub" | xclip -selection clipboard
          echo "✅ Copied to clipboard (X11)"
        elif command -v pbcopy >/dev/null 2>&1; then
          cat "$HOME/.ssh/id_ed25519.pub" | pbcopy
          echo "✅ Copied to clipboard (macOS)"
        else
          echo "💡 Copy the key above to add to GitHub/servers"
        fi
      '')
    ];

    # Enable SSH agent service (Linux only)
    services.ssh-agent.enable = mkIf pkgs.stdenv.isLinux true;
  };
}

