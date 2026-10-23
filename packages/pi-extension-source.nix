{
  pkgs,
  pname,
  version,
  url,
  hash,
  license,
}:
let
  sdk = "${pkgs.pi-coding-agent}/lib/node_modules/pi-monorepo";
in
pkgs.stdenvNoCC.mkDerivation {
  inherit pname version;
  src = pkgs.fetchurl { inherit url hash; };
  dontBuild = true;
  installPhase = ''
    mkdir -p "$out/lib/pi-extensions/${pname}"
    cp -R . "$out/lib/pi-extensions/${pname}/"
    mkdir -p "$out/lib/pi-extensions/${pname}/node_modules/@earendil-works"
    ln -s ${sdk} "$out/lib/pi-extensions/${pname}/node_modules/@earendil-works/pi-coding-agent"
    for name in pi-ai pi-agent-core pi-tui; do
      ln -s ${sdk}/node_modules/@earendil-works/"$name" "$out/lib/pi-extensions/${pname}/node_modules/@earendil-works/$name"
    done
    ln -s ${sdk}/node_modules/typebox "$out/lib/pi-extensions/${pname}/node_modules/typebox"
  '';
  passthru.packageRoot = "lib/pi-extensions/${pname}";
  meta = {
    inherit license;
    description = "Pinned Pi extension source, with host SDK peers and no installer";
  };
}
