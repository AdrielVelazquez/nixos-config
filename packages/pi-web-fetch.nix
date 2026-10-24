{ pkgs }:
let
  sdk = "${pkgs.pi-coding-agent}/lib/node_modules/pi-monorepo";
in
pkgs.buildNpmPackage {
  pname = "pi-web-access";
  version = "0.44.0";
  src = ./pi-web-fetch;
  nodejs = pkgs.nodejs_24;
  npmDeps = pkgs.importNpmLock { npmRoot = ./pi-web-fetch; };
  npmConfigHook = pkgs.importNpmLock.npmConfigHook;
  npmFlags = [
    "--ignore-scripts"
    "--legacy-peer-deps"
  ];
  dontNpmBuild = true;
  dontNpmInstall = true;
  installPhase = ''
    mkdir -p "$out"
    cp -R node_modules "$out/"
    mkdir -p "$out/node_modules/@earendil-works"
    ln -s ${sdk} "$out/node_modules/@earendil-works/pi-coding-agent"
    for name in pi-ai pi-agent-core pi-tui; do
      ln -s ${sdk}/node_modules/@earendil-works/"$name" "$out/node_modules/@earendil-works/$name"
    done
    ln -s ${sdk}/node_modules/typebox "$out/node_modules/typebox"
  '';
  passthru.packageRoot = "node_modules/pi-web-access";
  meta = {
    description = "Fixed Pi web dependency closure; runtime scripts and installers disabled";
    license = pkgs.lib.licenses.mit;
  };
}
