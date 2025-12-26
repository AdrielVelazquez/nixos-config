# modules/home-manager/ssh.nix
# SSH configuration with sops-encrypted keys
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.within.ssh;
in
{
  options.within.ssh = {
    enable = lib.mkEnableOption "Enables SSH with sops-encrypted keys";

    enableGitHubKeys = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable GitHub SSH configuration";
    };

    enableRedditKeys = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Reddit internal GitHub SSH configuration";
    };

    additionalHosts = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            hostname = lib.mkOption {
              type = lib.types.str;
              description = "SSH hostname";
            };
            user = lib.mkOption {
              type = lib.types.str;
              default = "git";
              description = "SSH user";
            };
            identityFile = lib.mkOption {
              type = lib.types.str;
              default = "~/.ssh/id_ed25519";
              description = "Path to SSH identity file";
            };
          };
        }
      );
      default = { };
      description = "Additional SSH host configurations";
    };
  };

  config = lib.mkIf cfg.enable {
    # Define sops secrets for SSH keys
    sops.secrets.ssh_private_key_ed25519 = {
      path = "${config.home.homeDirectory}/.ssh/id_ed25519";
    };

    sops.secrets.ssh_pub_key_ed25519 = {
      path = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
    };

    # Configure SSH
    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;

      matchBlocks = lib.mkMerge [
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
        (lib.mkIf cfg.enableGitHubKeys {
          "github.com" = {
            hostname = "github.com";
            user = "git";
            identityFile = "~/.ssh/id_ed25519";
            extraOptions.AddKeysToAgent = "yes";
          };
        })

        # Reddit internal GitHub
        (lib.mkIf cfg.enableRedditKeys {
          "github.snooguts.net" = {
            hostname = "github.snooguts.net";
            user = "git";
            identityFile = "~/.ssh/id_ed25519";
            extraOptions.AddKeysToAgent = "yes";
          };
        })

        # Additional user-defined hosts
        (lib.mapAttrs (_name: host: {
          hostname = host.hostname;
          user = host.user;
          identityFile = host.identityFile;
        }) cfg.additionalHosts)
      ];
    };

    # Ensure SSH directory and socket directory exist with correct permissions
    home.activation.setupSshDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD mkdir -p $HOME/.ssh
      $DRY_RUN_CMD chmod 700 $HOME/.ssh
      $DRY_RUN_CMD mkdir -p $HOME/.ssh/sockets
      $DRY_RUN_CMD chmod 700 $HOME/.ssh/sockets

      # Fix permissions on SSH keys if they exist
      if [ -f "$HOME/.ssh/id_ed25519" ]; then
        $DRY_RUN_CMD chmod 600 $HOME/.ssh/id_ed25519
      fi
      if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
        $DRY_RUN_CMD chmod 644 $HOME/.ssh/id_ed25519.pub
      fi
    '';

    # Helper scripts
    home.packages = [
      (pkgs.writeShellScriptBin "ssh-test-keys" ''
        #!/usr/bin/env bash

        GREEN='\033[0;32m'
        RED='\033[0;31m'
        YELLOW='\033[0;33m'
        NC='\033[0m'

        echo "SSH Key Configuration Test"
        echo "=============================="
        echo ""

        echo "Checking SSH key files..."
        if [ -f "$HOME/.ssh/id_ed25519" ]; then
          echo -e "  ''${GREEN}id_ed25519 exists''${NC}"
          echo "     Permissions: $(stat -c %a "$HOME/.ssh/id_ed25519" 2>/dev/null || stat -f %A "$HOME/.ssh/id_ed25519" 2>/dev/null)"
        else
          echo -e "  ''${RED}id_ed25519 missing''${NC}"
        fi

        if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
          echo -e "  ''${GREEN}id_ed25519.pub exists''${NC}"
          echo "     $(head -n1 "$HOME/.ssh/id_ed25519.pub" | cut -d' ' -f1,2 | cut -c1-60)..."
        else
          echo -e "  ''${RED}id_ed25519.pub missing''${NC}"
        fi

        echo ""
        echo "Testing SSH connections..."
        echo ""

        echo "Testing github.com..."
        if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
          echo -e "  ''${GREEN}GitHub authentication successful''${NC}"
        else
          echo -e "  ''${YELLOW}GitHub authentication response:''${NC}"
          ssh -T git@github.com 2>&1 | head -n 2 | sed 's/^/     /'
        fi

        echo ""

        if grep -q "github.snooguts.net" "$HOME/.ssh/config" 2>/dev/null; then
          echo "Testing github.snooguts.net..."
          if timeout 5 ssh -T git@github.snooguts.net 2>&1 | grep -q "successfully authenticated"; then
            echo -e "  ''${GREEN}Reddit GitHub authentication successful''${NC}"
          else
            echo -e "  ''${YELLOW}Reddit GitHub authentication response:''${NC}"
            timeout 5 ssh -T git@github.snooguts.net 2>&1 | head -n 2 | sed 's/^/     /' || echo "     (timeout or connection issue)"
          fi
        fi

        echo ""
        echo "SSH Configuration:"
        echo "   Config file: $HOME/.ssh/config"
        echo "   Socket dir: $HOME/.ssh/sockets"
        echo ""
        echo "To view your public key:"
        echo "   cat ~/.ssh/id_ed25519.pub"
      '')

      (pkgs.writeShellScriptBin "ssh-copy-public-key" ''
        #!/usr/bin/env bash

        GREEN='\033[0;32m'
        RED='\033[0;31m'
        NC='\033[0m'

        if [ ! -f "$HOME/.ssh/id_ed25519.pub" ]; then
          echo -e "''${RED}Public key not found at ~/.ssh/id_ed25519.pub''${NC}"
          exit 1
        fi

        echo "Your SSH public key:"
        echo ""
        cat "$HOME/.ssh/id_ed25519.pub"
        echo ""

        if command -v wl-copy >/dev/null 2>&1; then
          cat "$HOME/.ssh/id_ed25519.pub" | wl-copy
          echo -e "''${GREEN}Copied to clipboard (Wayland)''${NC}"
        elif command -v xclip >/dev/null 2>&1; then
          cat "$HOME/.ssh/id_ed25519.pub" | xclip -selection clipboard
          echo -e "''${GREEN}Copied to clipboard (X11)''${NC}"
        elif command -v pbcopy >/dev/null 2>&1; then
          cat "$HOME/.ssh/id_ed25519.pub" | pbcopy
          echo -e "''${GREEN}Copied to clipboard (macOS)''${NC}"
        else
          echo "Copy the key above to add to GitHub/servers"
        fi
      '')
    ];

  };
}
