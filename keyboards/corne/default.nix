# keyboards/corne/default.nix
# ZMK firmware for the Corne (crkbd) split keyboard, built with zmk-nix.
# Config source: keyboards/corne/config (vendored from AdrielVelazquez/zmk-config).
# Flash with: nix run .#corne-flash (double-tap reset on each half first).
{
  lib,
  buildSplitKeyboard,
}:

buildSplitKeyboard {
  name = "corne-firmware";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = ./config;
  };
  board = "nice_nano@2.0.0//zmk";
  shield = "corne_%PART%";
  # Central (left) half exposes the ZMK Studio USB-serial RPC interface.
  enableZmkStudio = true;
  zephyrDepsHash = "sha256-zDnYk7iavZLcuPRrl8QUMROnvikwBGOrDa5prc2cFtk=";
  meta = with lib; {
    description = "ZMK firmware for the Corne split keyboard";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
