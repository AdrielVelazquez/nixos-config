{ pkgs }:
pkgs.buildNpmPackage {
  pname = "pi-lsp";
  version = "0.15.1";
  src = ./pi-lsp;
  nodejs = pkgs.nodejs_24;
  npmDeps = pkgs.importNpmLock { npmRoot = ./pi-lsp; };
  npmConfigHook = pkgs.importNpmLock.npmConfigHook;
  npmFlags = [
    "--ignore-scripts"
    "--legacy-peer-deps"
  ];
  dontNpmBuild = true;
  dontNpmInstall = true;
  postInstall = import ./pi-lsp-path-push-diagnostics.nix + import ./pi-lsp-path-push-silence.nix;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -R node_modules "$out/"
    runHook postInstall
  '';
  passthru.packageRoot = "node_modules/@ian-pascoe/pi-lsp";
  meta = {
    description = "Pinned Pi LSP extension with fresh push-only edit diagnostics";
    license = pkgs.lib.licenses.mit;
  };
}
