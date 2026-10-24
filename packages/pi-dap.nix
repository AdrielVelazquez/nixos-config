{ pkgs }:

pkgs.buildNpmPackage {
  pname = "pi-dap";
  version = "0.10.1";
  src = ./pi-dap;
  nodejs = pkgs.nodejs_24;
  npmDeps = pkgs.importNpmLock { npmRoot = ./pi-dap; };
  npmConfigHook = pkgs.importNpmLock.npmConfigHook;
  # No lifecycle scripts run and no peer dependency is installed: Pi supplies its own copies.
  npmFlags = [
    "--ignore-scripts"
    "--legacy-peer-deps"
  ];
  dontNpmBuild = true;
  dontNpmInstall = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -R node_modules "$out/"
    runHook postInstall
  '';
  passthru.packageRoot = "node_modules/@ian-pascoe/pi-dap";
  meta = {
    description = "Pinned Pi DAP extension; debug adapters come from Nix, never from a runtime installer";
    license = pkgs.lib.licenses.mit;
  };
}
