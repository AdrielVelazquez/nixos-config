{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  openssl,
  zlib,
  stdenv,
}:
stdenvNoCC.mkDerivation rec {
  pname = "microsandbox";
  version = "0.7.11";
  src = fetchurl {
    url = "https://github.com/superradcompany/microsandbox/releases/download/v${version}/microsandbox-linux-x86_64.tar.gz";
    hash = "sha256-X8Igb741tHF0O9WvFeOTHNJDmgyLjm7wikk92rzcG0w=";
  };
  sourceRoot = ".";
  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = [
    openssl
    zlib
    stdenv.cc.cc.lib
  ];
  installPhase = ''
    runHook preInstall
    install -Dm755 msb "$out/libexec/msb"
    install -Dm644 libkrunfw.so.5.6.1 "$out/lib/libkrunfw.so.5.6.1"
    ln -s libkrunfw.so.5.6.1 "$out/lib/libkrunfw.so.5"
    ln -s libkrunfw.so.5 "$out/lib/libkrunfw.so"
    makeWrapper "$out/libexec/msb" "$out/bin/msb" \
      --set MSB_PATH "$out/libexec/msb" \
      --set MSB_LIBKRUNFW_PATH "$out/lib/libkrunfw.so.5.6.1" \
      --prefix LD_LIBRARY_PATH : "$out/lib"
    ln -s msb "$out/bin/microsandbox"
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    export HOME="$TMPDIR/home" MSB_HOME="$TMPDIR/runtime"
    mkdir -p "$HOME"
    "$out/bin/msb" --version
    "$out/bin/msb" --help >/dev/null
  '';
  meta = {
    description = "Local microVM sandbox runtime with its matching kernel firmware";
    homepage = "https://github.com/superradcompany/microsandbox";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "msb";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
