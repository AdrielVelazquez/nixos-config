{ pkgs }:
pkgs.callPackage ./pi-extension-source.nix {
  pname = "pi-zentui";
  version = "0.32.0";
  url = "https://registry.npmjs.org/pi-zentui/-/pi-zentui-0.32.0.tgz";
  hash = "sha512-DJHmMWyUkDd/7M4YAE+VfLNtQRMroQFryJsg5WkM/mzhJvFqYWcCzi7d7nM2QXKN1rS1Fwpszrnz6XAQAx3rFQ==";
  license = pkgs.lib.licenses.mit;
}
