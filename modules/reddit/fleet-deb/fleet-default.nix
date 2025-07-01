{
  stdenv,
  lib,
  dpkg,
  buildFHSEnv,
  ...
}:

let
  pname = "fleet-osquery";
  version = "1.27.0";
  arch = "amd64";
  src = /opt/fleet + "/${pname}_${version}_${arch}.deb";

  fleet-osquery = stdenv.mkDerivation rec {
    inherit version arch src;
    buildInputs = [ dpkg ];
    name = pname;
    sourceRoot = ".";

    unpackCmd = ''
      dpkg-deb -x "$src" .
    '';

    installPhase = ''
      cp -r ./ $out/
      realpath $out
    '';

    meta = with lib; {
      description = "Fleet Osquery";
      homepage = "";
      license = licenses.unfree;
      platforms = platforms.linux;
      maintainers = with maintainers; [ adriel ];
    };
  };
in
buildFHSEnv {
  name = "fq-bash";
  targetPkgs = pkgs: [
    pkgs.libnl
    pkgs.openssl
    pkgs.zlib
  ];

  extraInstallCommands = ''
    ln -s ${fleet-osquery}/* $out/
  '';

  runScript = "bash";
}
