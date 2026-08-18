# parts/system-manager.nix
{ inputs, localLib, ... }:

let
  inherit (localLib) systems;
  fleetPackages = import inputs.nixpkgs-fleet {
    system = systems.linux;
    config.allowUnfree = true;
  };
  fleetOverlay = _final: _prev: {
    inherit (fleetPackages) fleet-desktop fleet-orbit;
  };

  # Shared modules for system-manager configurations
  baseSystemModules = [
    inputs.nix-system-graphics.systemModules.default
    inputs.sops-nix.nixosModules.sops
    ../modules/shared/nix-cache-settings.nix
    (
      { pkgs, ... }:
      {
        config = {
          nixpkgs.hostPlatform = systems.linux;
          # reddit overlay disabled - causes SSH auth issues with sudo
          # nixpkgs.overlays = [ inputs.reddit.overlay ];
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

  mkSystemConfig =
    hostModule:
    inputs.system-manager.lib.makeSystemConfig {
      overlays = [ fleetOverlay ];
      modules = baseSystemModules ++ [ hostModule ];
    };

in
{
  flake.systemConfigs = {
    # CachyOS on Framework 13
    cachyos-framework13 = mkSystemConfig ../hosts/cachyos-framework13-system-manager/configuration.nix;
  };

  perSystem =
    { lib, system, ... }:
    lib.mkIf (system == systems.linux) {
      apps.system-manager = {
        type = "app";
        program = "${inputs.system-manager.packages.${system}.default}/bin/system-manager";
        meta.description = "Manage the host system with system-manager";
      };
    };
}
