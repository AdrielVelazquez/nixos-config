# parts/formatter.nix
{ inputs, ... }:

{
  perSystem =
    { pkgs, ... }:
    {
      formatter = pkgs.nixfmt;
    };
}
