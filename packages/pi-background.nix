{ pkgs }:
pkgs.callPackage ./pi-extension-source.nix {
  pname = "pi-background";
  version = "0.4.0";
  url = "https://registry.npmjs.org/pi-background/-/pi-background-0.4.0.tgz";
  hash = "sha512-IGtooEffgtqcFg3x7/KUEEnNvmf8O9DTiGOcVIsMgnvz4ZMI0kmW48EEiuRcZjSkW3B1Jalhmv/uzT8aeaR9BA==";
  license = pkgs.lib.licenses.mit;
}
