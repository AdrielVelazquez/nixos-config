{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Test Linux 7.0.10 from master for the MediaTek Bluetooth resume fix.
    # Temporarily pin PR #523596 for OpenRazer 3.12.3 so linux_7_0 builds.
    # Switch back to the main nixpkgs input once nixos-unstable has both fixes.
    nixpkgs-kernel-master.url = "github:r-ryantm/nixpkgs/436d0dc2f2c1c949fcc575940ccf5f00b32d9424";

    # nixpkgs-nvidia.url = "github:NixOS/nixpkgs/master";

    nixpkgs-antigravity.url = "github:NixOS/nixpkgs/master";

    superpowers = {
      url = "github:obra/superpowers";
      flake = false;
    };

    android-skills = {
      url = "github:android/skills";
      flake = false;
    };

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
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
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia = {
      url = "github:noctalia-dev/noctalia-shell/v5";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    let
      localLib = import ./parts/lib.nix { inherit inputs; };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      _module.args = { inherit localLib; };

      imports = [
        ./parts/nixos.nix
        ./parts/darwin.nix
        ./parts/home-manager.nix
        ./parts/system-manager.nix
        ./parts/formatter.nix
        ./parts/checks.nix
      ];
    };
}
