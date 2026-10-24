{ pkgs }:
pkgs.callPackage ./pi-extension-source.nix {
  pname = "pi-ast-grep";
  version = "0.4.2";
  url = "https://registry.npmjs.org/@juvio15/pi-ast-grep/-/pi-ast-grep-0.4.2.tgz";
  hash = "sha512-ohv9dK3Z2dTO7N+oSuCgYKD50U9gkFTmmH5wabVXB3SJNisBxlJpNmO/4kqRkvGBV/rF44YnKjdsvcroD59atQ==";
  license = pkgs.lib.licenses.asl20;
}
