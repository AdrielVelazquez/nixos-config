{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Fleet Orbit/Desktop 1.58.0 fork, scoped to the Framework system-manager
    # configuration through a two-package overlay. See TODO.md.
    nixpkgs-fleet.url = "github:AdrielVelazquez/nixpkgs/15b70b1d5954a2573a7d6a0228eb2c5de4733db8";

    # nixpkgs-nvidia.url = "github:NixOS/nixpkgs/master";

    superpowers = {
      url = "github:obra/superpowers";
      flake = false;
    };

    android-skills = {
      url = "github:android/skills";
      flake = false;
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ai-kitten = {
      url = "git+ssh://git@github.com/AdrielVelazquez/aiKitten.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    reddit = {
      url = "git+ssh://git@github.snooguts.net/reddit/reddit-nix.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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

    system-manager = {
      url = "github:numtide/system-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-system-graphics = {
      url = "github:soupglasses/nix-system-graphics";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-group-tabs = {
      url = "git+ssh://git@github.com/AdrielVelazquez/zen-group-tabs.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    niri = {
      url = "github:niri-wm/niri";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia = {
      url = "github:noctalia-dev/noctalia";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      nixpkgs,
      home-manager,
      system-manager,
      ...
    }:
    let
      system = "x86_64-linux";
      darwinSystem = "aarch64-darwin";
      lib = nixpkgs.lib;
      pkgs = nixpkgs.legacyPackages.${system};
      specialArgs = { inherit inputs; };
      niriPackage = inputs.niri.packages.${system}.niri;

      homeManagerIntegration = {
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          extraSpecialArgs = specialArgs;
          sharedModules = [ inputs.sops-nix.homeManagerModules.sops ];
          backupFileExtension = "hm-backup";
        };
      };

      redditOverlayModule = {
        nixpkgs.overlays = [ inputs.reddit.overlay ];
      };

      fleetPackages = import inputs.nixpkgs-fleet {
        inherit system;
        config.allowUnfree = true;
      };
      fleetOverlay = _final: _prev: {
        inherit (fleetPackages) fleet-desktop fleet-orbit;
      };

      nixosConfigurations = {
        razer14 = nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = [
            ./modules/profiles/laptop.nix
            inputs.sops-nix.nixosModules.sops
            inputs.home-manager.nixosModules.home-manager
            homeManagerIntegration
            ./hosts/razer14/configuration.nix
            { home-manager.users.adriel = import ./users/adriel; }
          ];
        };

        dell-plex = nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = [
            ./modules/profiles/desktop.nix
            inputs.sops-nix.nixosModules.sops
            inputs.home-manager.nixosModules.home-manager
            homeManagerIntegration
            ./hosts/dell-plex-server/configuration.nix
            { home-manager.users.adriel = import ./users/adriel-dell; }
          ];
        };
      };

      homeConfigurations = {
        razer14 = home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            inherit system;
            config = {
              allowUnfree = true;
              cudaCapabilities = [ "12.0" ];
            };
          };
          extraSpecialArgs = specialArgs;
          modules = [
            inputs.sops-nix.homeManagerModules.sops
            ./users/adriel
          ];
        };

        cachyos-framework13 = home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          extraSpecialArgs = specialArgs;
          modules = [
            inputs.sops-nix.homeManagerModules.sops
            redditOverlayModule
            ./users/adriel-cachyos
          ];
        };
      };

      darwinConfigurations = {
        PNH46YXX3Y = inputs.nix-darwin.lib.darwinSystem {
          system = darwinSystem;
          specialArgs = specialArgs;
          modules = [
            ./hosts/reddit-mac/configuration.nix
            inputs.nix-homebrew.darwinModules.nix-homebrew
            {
              nix-homebrew = {
                enable = true;
                user = "adriel.velazquez";
                taps = {
                  "homebrew/homebrew-core" = inputs.homebrew-core;
                  "homebrew/homebrew-cask" = inputs.homebrew-cask;
                  "homebrew/homebrew-bundle" = inputs.homebrew-bundle;
                };
              };
            }
            inputs.home-manager.darwinModules.home-manager
            homeManagerIntegration
            { home-manager.users."adriel.velazquez" = import ./users/adriel.velazquez; }
            redditOverlayModule
          ];
        };
      };

      frameworkBaseModules = [
        inputs.nix-system-graphics.systemModules.default
        inputs.sops-nix.nixosModules.sops
        ./modules/shared/nix-cache-settings.nix
        (
          { pkgs, ... }:
          {
            config = {
              _module.args = { inherit niriPackage; };
              nixpkgs.hostPlatform = system;
              system-manager.allowAnyDistro = true;
              system-graphics = {
                enable = true;
                package = pkgs.mesa;
                package32 = pkgs.pkgsi686Linux.mesa;
              };
            };
          }
        )
      ];

      systemConfigs = {
        cachyos-framework13 = system-manager.lib.makeSystemConfig {
          overlays = [ fleetOverlay ];
          modules = frameworkBaseModules ++ [
            ./hosts/cachyos-framework13-system-manager/configuration.nix
          ];
        };
      };
    in
    {
      inherit
        nixosConfigurations
        darwinConfigurations
        homeConfigurations
        systemConfigs
        ;

      apps.${system}.system-manager = {
        type = "app";
        program = "${system-manager.packages.${system}.default}/bin/system-manager";
        meta.description = "Manage the host system with system-manager";
      };

      formatter.${system} = pkgs.nixfmt-tree;
      formatter.${darwinSystem} = nixpkgs.legacyPackages.${darwinSystem}.nixfmt-tree;

      checks.${system} = import ./checks.nix {
        inherit
          inputs
          lib
          pkgs
          system
          nixosConfigurations
          darwinConfigurations
          homeConfigurations
          systemConfigs
          ;
        src = ./.;
      };

      checks.${darwinSystem} =
        let
          sharedDarwinChecks = import ./checks.nix {
            inherit
              inputs
              lib
              system
              nixosConfigurations
              darwinConfigurations
              homeConfigurations
              systemConfigs
              ;
            pkgs = nixpkgs.legacyPackages.${darwinSystem};
            src = ./.;
          };
        in
        {
          inherit (sharedDarwinChecks)
            configuration-contract
            justfile-contract
            lua-format
            nix-format
            nvim-regressions
            shell-syntax
            ;
          reddit-mac = darwinConfigurations.PNH46YXX3Y.config.system.build.toplevel;
        };
    };
}
