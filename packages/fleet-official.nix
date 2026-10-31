{ pkgs }:
let
  orbit = (pkgs.fleet-orbit.override { buildGoModule = pkgs.buildGo127Module; }).overrideAttrs {
    version = "1.63.0";
    src = pkgs.fetchFromGitHub {
      owner = "fleetdm";
      repo = "fleet";
      tag = "orbit-v1.63.0";
      hash = "sha256-cKF1nE9kK22EfB0Ky+vp8QaBDYcZ00mwWNU9BJwWAx8=";
    };
    patches = [ ];
    vendorHash = "sha256-mnjllTf4m8Kirx0TKKWzr0haA/zwiZMWYEYRifVeFpQ=";
  };
  desktop =
    (pkgs.fleet-desktop.override {
      buildGoModule = pkgs.buildGo127Module;
      fleet-orbit = orbit;
    }).overrideAttrs
      {
        vendorHash = orbit.vendorHash;
      };
in
{
  inherit orbit desktop;
}
