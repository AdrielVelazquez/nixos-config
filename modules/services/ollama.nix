{ lib, config, pkgs, ... }:

with lib;

let cfg = config.within.ollama;
in {
  options.within.ollama.enable = mkEnableOption "Enables ollama Settings";

  config = mkIf cfg.enable {
    services.ollama.enable = true;
    services.ollama.acceleration = "cuda";
    # pkgs.ollama.acceleration = "cuda";
  };
}
