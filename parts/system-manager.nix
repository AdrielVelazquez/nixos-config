# parts/system-manager.nix
# system-manager configurations (for non-NixOS Linux system services)
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
    ../hosts/reddit-framework13-system-manager
  ];

  mkSystemConfig = modules: inputs.system-manager.lib.makeSystemConfig {
    modules = baseSystemModules ++ modules;
  };

in
{
  flake.systemConfigs = {
    # Named configuration for pop-os hostname
    pop-os = mkSystemConfig [ ];

    # Keep default as an alias
    default = mkSystemConfig [ ];
  };
}
