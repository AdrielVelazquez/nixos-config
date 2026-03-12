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
    # Named configuration for pop-os hostname
    pop-os = mkSystemConfig ../hosts/reddit-framework13-system-manager;

    # Keep default as an alias
    default = mkSystemConfig ../hosts/reddit-framework13-system-manager;

    # CachyOS on Framework 13
    cachyos-framework = mkSystemConfig ../hosts/cachyos-framework13-system-manager;
  };
}
