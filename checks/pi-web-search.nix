{ pkgs, ... }:
{
  # The throttled-provider cooldown the web-access wrapper puts in front of fetch.
  pi-web-search = pkgs.runCommand "pi-web-search-check" { nativeBuildInputs = [ pkgs.nodejs_24 ]; } ''
    cd ${../.}
    node --test tests/pi/search-cooldown.test.mjs
    touch "$out"
  '';
}
