{ ... }:

{
  imports = [
    ./docker.nix
    ./endpoint-agent-limits.nix
    ./falcon-sensor.nix
    ./kanata.nix
    ./mediatek-wifi.nix
    ./niri.nix
    ./sops.nix
    ./orbit.nix
    ./zsa-keyboard.nix
    ./snoocert.nix
  ];
}
