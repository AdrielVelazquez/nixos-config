# parts/formatter.nix
# Formatter configuration for `nix fmt`
{ inputs, ... }:

{
  perSystem =
    { pkgs, ... }:
    {
      formatter = pkgs.nixfmt-rfc-style;
    };
}
