{
  lib,
  config,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.within.cosmic;
in
{
  options.within.cosmic.enable = mkEnableOption "Enables cosmic desktopManager";
  # cosmic does lot's of system changes, so we need to call this outside of homemanager
  config = mkIf cfg.enable {
    nix.settings = {
      substituters = [ "https://cosmic.cachix.org/" ];
      trusted-public-keys = [ "cosmic.cachix.org-1:Dya9IyXD4xdBehWjrkPv6rtxpmMdRel02smYzA85dPE=" ];
    };
    services.desktopManager.cosmic.enable = true;
    services.displayManager.cosmic-greeter.enable = true;

  };
}
