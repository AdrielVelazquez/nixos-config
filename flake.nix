# ~/.nixos/flake.nix
{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ============================================================================
    # Secrets
    # ============================================================================
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ============================================================================
    # Applications
    # ============================================================================
    solaar = {
      url = "github:Svenum/Solaar-Flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ============================================================================
    # Reddit Specific
    # ============================================================================
    reddit = {
      url = "git+ssh://git@github.snooguts.net/reddit/reddit-nix.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ============================================================================
    # macOS Specific
    # ============================================================================
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";

    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };

    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };

    homebrew-bundle = {
      url = "github:homebrew/homebrew-bundle";
      flake = false;
    };

    # ============================================================================
    # Non-NixOS Linux Systems
    # ============================================================================
    system-manager = {
      url = "github:numtide/system-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-system-graphics = {
      url = "github:soupglasses/nix-system-graphics";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, ... }@inputs:
    let
      # ============================================================================
      # Constants
      # ============================================================================
      systems = {
        linux = "x86_64-linux";
        darwin = "aarch64-darwin";
      };

      users = {
        adriel = "adriel";
        adrielVelazquez = "adriel.velazquez";
      };

      # ============================================================================
      # Common Configurations
      # ============================================================================
      commonSpecialArgs = { inherit inputs; };

      # Shared home-manager settings for all configurations
      mkHomeManagerConfig =
        {
          useGlobalPkgs ? true,
          useUserPackages ? true,
          extraModules ? [ ],
        }:
        {
          home-manager = {
            inherit useGlobalPkgs useUserPackages;
            extraSpecialArgs = commonSpecialArgs;
            sharedModules = [ inputs.sops-nix.homeManagerModules.sops ] ++ extraModules;
          };
        };

      # Reddit overlay module (reused across configurations)
      redditOverlayModule = {
        nixpkgs.overlays = [ inputs.reddit.overlay ];
      };

      # ============================================================================
      # Helper Functions
      # ============================================================================

      # Create a home-manager user configuration module
      mkUser = username: userConfig: {
        home-manager.users.${username} = import userConfig;
      };

      # NixOS configuration builder
      mkNixosConfig =
        {
          system ? systems.linux,
          hostConfig,
          username ? users.adriel,
          userConfig ? ./users/adriel.nix,
          extraModules ? [ ],
          useGlobalPkgs ? true,
        }:
        inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = commonSpecialArgs;
          modules = [
            # Common modules for all NixOS hosts
            inputs.solaar.nixosModules.default
            inputs.sops-nix.nixosModules.sops
            inputs.home-manager.nixosModules.home-manager
            (mkHomeManagerConfig { inherit useGlobalPkgs; })

            # Host-specific configuration
            hostConfig
            (mkUser username userConfig)
          ]
          ++ extraModules;
        };

      # Darwin (macOS) configuration builder
      mkDarwinConfig =
        {
          system ? systems.darwin,
          hostConfig,
          username,
          userConfig,
          extraModules ? [ ],
          homebrewUser ? username,
        }:
        inputs.nix-darwin.lib.darwinSystem {
          inherit system;
          specialArgs = commonSpecialArgs;
          modules = [
            hostConfig
            inputs.nix-homebrew.darwinModules.nix-homebrew
            {
              nix-homebrew = {
                enable = true;
                user = homebrewUser;
                taps = {
                  "homebrew/homebrew-core" = inputs.homebrew-core;
                  "homebrew/homebrew-cask" = inputs.homebrew-cask;
                  "homebrew/homebrew-bundle" = inputs.homebrew-bundle;
                };
              };
            }
            inputs.home-manager.darwinModules.home-manager
            (mkHomeManagerConfig { })
            (mkUser username userConfig)
          ]
          ++ extraModules;
        };

      # Standalone home-manager configuration builder
      mkHomeConfig =
        {
          system ? systems.linux,
          userConfig,
          extraModules ? [ ],
          overlays ? [ ],
        }:
        inputs.home-manager.lib.homeManagerConfiguration {
          pkgs = import inputs.nixpkgs {
            inherit system overlays;
            config.allowUnfree = true;
          };
          extraSpecialArgs = commonSpecialArgs;
          modules = [
            inputs.sops-nix.homeManagerModules.sops
          ]
          ++ extraModules
          ++ [ userConfig ];
        };

    in
    {
      # ============================================================================
      # System Manager Configurations (Non-NixOS Linux)
      # ============================================================================
      systemConfigs.default = inputs.system-manager.lib.makeSystemConfig {
        modules = [
          inputs.nix-system-graphics.systemModules.default
          {
            config = {
              nixpkgs.hostPlatform = systems.linux;
              nixpkgs.overlays = [ inputs.reddit.overlay ];
              system-manager.allowAnyDistro = true;
              system-graphics.enable = true;
            };
          }
          ./hosts/reddit-framework13-system-manager
        ];
      };

      # ============================================================================
      # NixOS Configurations
      # ============================================================================
      nixosConfigurations = {
        razer14 = mkNixosConfig {
          hostConfig = ./hosts/razer14/configuration.nix;
        };

        dell = mkNixosConfig {
          hostConfig = ./hosts/dell-plex-server/configuration.nix;
        };

        # Note: reddit-framework13 uses system-manager, not NixOS
      };

      # ============================================================================
      # Darwin (macOS) Configurations
      # ============================================================================
      darwinConfigurations = {
        PNH46YXX3Y = mkDarwinConfig {
          hostConfig = ./hosts/reddit-mac/configuration.nix;
          username = users.adrielVelazquez;
          userConfig = ./users/adriel.velazquez.nix;
          extraModules = [ redditOverlayModule ];
        };
      };

      # ============================================================================
      # Standalone Home Manager Configurations
      # ============================================================================
      homeConfigurations = {
        adriel = mkHomeConfig {
          userConfig = ./users/adriel.nix;
        };

        reddit-framework13 = mkHomeConfig {
          userConfig = ./users/adriel.velazquez.linux.nix;
          extraModules = [ redditOverlayModule ];
        };
      };

      # ============================================================================
      # Development Shells
      # ============================================================================
      devShells = {
        ${systems.linux} = {
          python = import ./dev-shells/python.nix {
            pkgs = inputs.nixpkgs.legacyPackages.${systems.linux};
          };
          default = self.devShells.${systems.linux}.python;
        };
      };

      # ============================================================================
      # Formatter (nix fmt)
      # ============================================================================
      formatter = {
        ${systems.linux} = inputs.nixpkgs.legacyPackages.${systems.linux}.nixfmt-rfc-style;
        ${systems.darwin} = inputs.nixpkgs.legacyPackages.${systems.darwin}.nixfmt-rfc-style;
      };

      # ============================================================================
      # Flake Checks (validate configurations build)
      # ============================================================================
      checks = {
        ${systems.linux} = {
          # NixOS configuration checks
          razer14 = self.nixosConfigurations.razer14.config.system.build.toplevel;
          dell = self.nixosConfigurations.dell.config.system.build.toplevel;

          # Home Manager configuration checks
          home-adriel = self.homeConfigurations.adriel.activationPackage;
          home-reddit-framework13 = self.homeConfigurations.reddit-framework13.activationPackage;
        };
        ${systems.darwin} = {
          # Darwin configuration check
          reddit-mac = self.darwinConfigurations.PNH46YXX3Y.config.system.build.toplevel;
        };
      };
    };
}
