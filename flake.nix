{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Follow upstream V2 development until nixpkgs provides a working V2 package.
    # `nix flake update opencode` advances the locked revision. See TODO.md.
    # Its own nixpkgs supplies the Bun used to calibrate node_modules hashes.
    opencode.url = "github:anomalyco/opencode/v2";

    # Fleet Orbit/Desktop 1.59.0 fork, scoped to the Framework system-manager
    # configuration through a two-package overlay. See TODO.md.
    nixpkgs-fleet.url = "github:AdrielVelazquez/nixpkgs/fleet_orbit_1-55_1-58";

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
      # PR #984 replaces the removed Go 1.25 builder. Revisit in TODO.md.
      url = "github:Mic92/sops-nix/16954c1c360c3dc4d4b3b3e64df59f7e89452cb1";
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
      };

      homeConfigurations = {
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
      inherit nixosConfigurations homeConfigurations systemConfigs;

      apps.${system}.system-manager = {
        type = "app";
        program = "${system-manager.packages.${system}.default}/bin/system-manager";
        meta.description = "Manage the host system with system-manager";
      };

      formatter.${system} = pkgs.nixfmt-tree;

      checks.${system} = import ./checks.nix {
        inherit
          inputs
          lib
          pkgs
          system
          nixosConfigurations
          homeConfigurations
          systemConfigs
          ;
        src = ./.;
      };
    };
}
