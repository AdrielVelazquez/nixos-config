# parts/dev-shells.nix
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
