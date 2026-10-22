{ pkgs }:
pkgs.buildNpmPackage {
  pname = "pi-subagents";
  version = "0.80.0";
  src = ./pi-subagents;
  nodejs = pkgs.nodejs_24;
  npmDeps = pkgs.importNpmLock { npmRoot = ./pi-subagents; };
  npmConfigHook = pkgs.importNpmLock.npmConfigHook;
  npmFlags = [
    "--ignore-scripts"
    "--legacy-peer-deps"
  ];
  dontNpmBuild = true;
  dontNpmInstall = true;
  postInstall = import ./pi-subagents-path-required-mcp.nix;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -R node_modules "$out/"
    runHook postInstall
  '';
  passthru.packageRoot = "node_modules/pi-subagents";
  meta = {
    description = "Pinned native Pi subagent extension; no runtime installer";
    license = pkgs.lib.licenses.mit;
  };
}
