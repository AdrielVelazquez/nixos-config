# parts/dev-shells.nix
# Development shell configurations
{ inputs, ... }:

{
  perSystem =
    { pkgs, system, ... }:
    {
      devShells = {
        python = import ../dev-shells/python.nix { inherit pkgs; };
      };
    };
}

