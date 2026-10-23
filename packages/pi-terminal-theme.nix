{ pkgs }:
pkgs.callPackage ./pi-extension-source.nix {
  pname = "pi-terminal-theme";
  version = "0.2.0";
  url = "https://registry.npmjs.org/pi-terminal-theme/-/pi-terminal-theme-0.2.0.tgz";
  hash = "sha512-lAqHu1vqiWggOcBrSp6w/c8H3E1cPUjc4VBb/4FzCk4a/E9QGh8UAMngtVqinrABd/58ervWxn36S5TK8AsEOA==";
  license = pkgs.lib.licenses.mit;
}
