# ~/.nixos/flake.nix
{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # ============================================================================
    # Flake Structure
    # ============================================================================
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    # ============================================================================
    # Home Manager
    # ============================================================================
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
    inputs@{ flake-parts, ... }:
    let
      # Shared library - injected into all parts via _module.args
      localLib = import ./parts/lib.nix { inherit inputs; };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      # Define which systems to support for perSystem options
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      # Make localLib available to all parts
      _module.args = { inherit localLib; };

      # Import all the parts
      imports = [
        ./parts/nixos.nix
        ./parts/darwin.nix
        ./parts/home-manager.nix
        ./parts/system-manager.nix
        ./parts/dev-shells.nix
        ./parts/formatter.nix
        ./parts/checks.nix
      ];
    };
}
