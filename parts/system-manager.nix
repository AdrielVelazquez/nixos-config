# parts/system-manager.nix
{ inputs, localLib, ... }:

let
  inherit (localLib) systems;

  # Shared modules for system-manager configurations
  baseSystemModules = [
    inputs.nix-system-graphics.systemModules.default
    {
      config = {
        nixpkgs.hostPlatform = systems.linux;
        # reddit overlay disabled - causes SSH auth issues with sudo
        # nixpkgs.overlays = [ inputs.reddit.overlay ];
        system-manager.allowAnyDistro = true;
        system-graphics.enable = true;
      };
    }
  ];

  mkSystemConfig =
    hostModule:
    inputs.system-manager.lib.makeSystemConfig {
      modules = baseSystemModules ++ [ hostModule ];
    };

in
{
  flake.systemConfigs = {
    # CachyOS on Framework 13
    cachyos-framework = mkSystemConfig ../hosts/cachyos-framework13-system-manager;

    default = mkSystemConfig ../hosts/cachyos-framework13-system-manager;
  };
}
