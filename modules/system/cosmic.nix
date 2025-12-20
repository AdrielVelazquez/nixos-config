# modules/system/cosmic.nix
{ lib, config, ... }:

let
  cfg = config.within.cosmic;
in
{
  options.within.cosmic.enable = lib.mkEnableOption "Enables COSMIC desktop environment";

  config = lib.mkIf cfg.enable {
    nix.settings = {
      substituters = [ "https://cosmic.cachix.org/" ];
      trusted-public-keys = [ "cosmic.cachix.org-1:Dya9IyXD4xdBehWjrkPv6rtxpmMdRel02smYzA85dPE=" ];
    };

    services.desktopManager.cosmic.enable = true;
    services.displayManager.cosmic-greeter.enable = true;
  };
}
