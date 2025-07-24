{
  stdenv,
  lib,
  dpkg,
  buildFHSEnv,
  requireFile, # Added requireFile to the function arguments
  ...
}:

let
  pname = "duo-desktop";
  version = "latest";
  arch = "amd64";

  # 1. Calculate the hash of your .deb file and add it here.
  #    Run: nix hash file --type sha256 duo-desktop-latest.amd64.deb
  hash = "sha256-y0GnN3JcyuL9kwudKzoqT5Na0ivhhHefVrzO6Kh0QAY=";

  # 2. Use `requireFile` to define the source, just like in your fleet package.
  src = requireFile rec {
    name = "${pname}-${version}.${arch}.deb";
    inherit hash;
    url = "https://desktop.pkg.duosecurity.com/duo-desktop-latest.amd64.deb"; # Optional: for user reference
    message = ''
      Could not find ${name} in the Nix store.
      Please download it from https://desktop.pkg.duosecurity.com/duo-desktop-latest.amd64.deb and add it to the store, for example:
      nix-store --add-fixed sha256 ${name}
    '';
  };

  duo-desktop = stdenv.mkDerivation rec {
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
      description = "Duo Desktop";
      homepage = "https://desktop.pkg.duosecurity.com/duo-desktop-latest.amd64.deb";
      license = licenses.unfree;
      platforms = platforms.linux;
    };
  };

in
# The FHS environment wrapper remains the same.
buildFHSEnv {
  name = "dd-bash";
  targetPkgs = pkgs: [
    pkgs.libnl
    pkgs.openssl
    pkgs.zlib
    pkgs.icu.dev
    pkgs.icu
  ];

  extraInstallCommands = ''
    ln -s ${duo-desktop}/* $out/
  '';

  runScript = "bash";
}
