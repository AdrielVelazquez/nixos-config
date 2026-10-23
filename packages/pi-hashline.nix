{ pkgs }:

pkgs.buildNpmPackage {
  pname = "pi-hashline";
  version = "0.0.10";
  src = ./pi-hashline;
  nodejs = pkgs.nodejs_24;
  npmDeps = pkgs.importNpmLock { npmRoot = ./pi-hashline; };
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
  passthru.packageRoot = "node_modules/@deathbeam/pi-hashline";
  meta = {
    description = "Pinned hash-anchored read, edit and grep for Pi; grep uses the ripgrep on PATH, which Pi's own wrapper supplies";
    license = pkgs.lib.licenses.mit;
  };
}
