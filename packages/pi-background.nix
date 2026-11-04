{ pkgs }:
let
  rev = "96fffeea461256aee8c39a6b7de89af8b6011a75";
in
(pkgs.callPackage ./pi-extension-source.nix {
  pname = "pi-background";
  version = "0.4.2-unstable-2026-11-04";
  # Temporary test pin for the fork's feat/background-job-navigation branch.
  url = "https://github.com/AdrielVelazquez/pi-extensions/archive/${rev}.tar.gz";
  hash = "sha256-v5Z3jMYhIhh7x6bsLMT900/nKK6zkGvVTwNg0Idt+6Q=";
  license = pkgs.lib.licenses.mit;
}).overrideAttrs
  {
    sourceRoot = "pi-extensions-${rev}/packages/pi-background";
  }
