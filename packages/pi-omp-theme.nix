{ pkgs }:
(pkgs.callPackage ./pi-extension-source.nix {
  pname = "pi-omp-theme";
  version = "1.0.26";
  url = "https://registry.npmjs.org/@nguyenquangthai/pi-omp-theme/-/pi-omp-theme-1.0.26.tgz";
  hash = "sha512-JMXETWk+4Zdz5FACxJYbqBtySPNZH/dV1i2DUKFgtuS1jQ0w6wpzMOQZ2XDTSGUcLH3KYgtV6csa/92RRyyzAw==";
  license = pkgs.lib.licenses.mit;
}).overrideAttrs
  (old: {
    installPhase =
      old.installPhase
      + (import ./pi-omp-theme-path-rounded-boxed-frame.nix)
      + (import ./pi-omp-theme-path-editor-mouse.nix);
  })
