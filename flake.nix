{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Kernel 7.0.8 regresses the Razer 14 MediaTek Bluetooth adapter. Keep the
    # laptop kernel package set on the nixpkgs commit that introduced 7.0.6 so
    # regular nixpkgs flake updates do not pull in the bad 7.0.8 kernel.
    nixpkgs-kernel-7_0_6.url = "github:NixOS/nixpkgs/cdfeb927c27f970928665b02d200884b05c9d18e";

    # nixpkgs-nvidia.url = "github:NixOS/nixpkgs/master";

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

    walker = {
      url = "github:abenz1267/walker";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ironbar = {
      url = "github:JakeStanger/ironbar";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents.url = "github:numtide/llm-agents.nix";
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
