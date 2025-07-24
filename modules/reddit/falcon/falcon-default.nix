{
  stdenv,
  lib,
  dpkg,
  buildFHSEnv,
  requireFile, # Added requireFile to the function arguments
  ...
}:

let
  pname = "falcon-sensor";
  version = "7.26.0-17905";
  arch = "amd64";

  # 1. Calculate the hash of your .deb file and add it here.
  #    Run: nix hash file --type sha256 /path/to/falcon-sensor_7.26.0-17905_amd64.deb
  hash = "sha256-It2M+m48DOvyZws1EqVu/t/22FXCs0CTX+uP4VmdepQ=";

  # 2. Use `requireFile` to define the source, just like in your fleet package.
  src = requireFile rec {
    name = "${pname}_${version}_${arch}.deb";
    inherit hash;
    url = "https://www.crowdstrike.com/"; # Optional: for user reference
    message = ''
      Could not find ${name} in the Nix store.
      Please download it from the CrowdStrike portal and add it to the store, for example:
      nix-store --add-fixed sha256 ${name}
    '';
  };

  falcon-sensor = stdenv.mkDerivation rec {
    inherit
      pname
      version
      arch
      src
      ;

    nativeBuildInputs = [ dpkg ];
    sourceRoot = ".";

    unpackCmd = ''
      dpkg-deb -x "$src" .
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r ./* $out/
      runHook postInstall
    '';

    meta = with lib; {
      description = "Crowdstrike Falcon Sensor";
      homepage = "https://www.crowdstrike.com/";
      license = licenses.unfree;
      platforms = platforms.linux;
    };
  };

in
# The FHS environment wrapper remains the same.
buildFHSEnv {
  name = "fs-bash";
  targetPkgs = pkgs: [
    pkgs.libnl
    pkgs.openssl
    pkgs.zlib
  ];

  extraInstallCommands = ''
    ln -s ${falcon-sensor}/* $out/
  '';

  runScript = "bash";
}
# {
#   stdenv,
#   lib,
#   dpkg,
#   buildFHSEnv,
#   ...
# }:
#
# let
#   pname = "falcon-sensor";
#   version = "7.26.0-17905";
#   arch = "amd64";
#   # src = ./${pname}_${version}_${arch}.deb;
#   src = /opt/CrowdStrike/${pname}_${version}_${arch}.deb;
#
#   falcon-sensor = stdenv.mkDerivation rec {
#     inherit version arch src;
#     buildInputs = [ dpkg ];
#     name = pname;
#     sourceRoot = ".";
#
#     unpackCmd = ''
#       dpkg-deb -x "$src" .
#     '';
#
#     installPhase = ''
#       cp -r ./ $out/
#       realpath $out
#     '';
#
#     meta = with lib; {
#       description = "Crowdstrike Falcon Sensor";
#       homepage = "https://www.crowdstrike.com/";
#       license = licenses.unfree;
#       platforms = platforms.linux;
#       maintainers = with maintainers; [ ravloony ];
#     };
#   };
# in
# buildFHSEnv {
#   name = "fs-bash";
#   targetPkgs = pkgs: [
#     pkgs.libnl
#     pkgs.openssl
#     pkgs.zlib
#   ];
#
#   extraInstallCommands = ''
#     ln -s ${falcon-sensor}/* $out/
#   '';
#
#   runScript = "bash";
# }
