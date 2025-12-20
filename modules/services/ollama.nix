# modules/services/ollama.nix
{ lib, config, pkgs, ... }:

let
  cfg = config.within.ollama;
  cudaEnabled = config.within.cuda.enable or false;
in
{
  options.within.ollama.enable = lib.mkEnableOption "Enables Ollama AI";

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      services.ollama.enable = true;
    })

    (lib.mkIf (cfg.enable && cudaEnabled) {
      environment.systemPackages = [ pkgs.cudatoolkit ];
      services.ollama.package = pkgs.ollama-cuda;
    })
  ];
}
