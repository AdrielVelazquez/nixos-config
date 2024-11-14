{
  lib,
  config,
  pkgs,
  builtins,
  ...
}:

with lib;

let
  cfg = config.within.ollama;
  cudaEnable = config.within.cuda;
in
{
  options.within.ollama.enable = mkEnableOption "Enables ollama Settings";
  # config = mkIf cfg.enable and cudaEnable.enable {
  #   builtins.trace = "Dual Enabling is working" ;
  #   services.ollama.enable = true;
  # };
  config = mkMerge [
    (mkIf cfg.enable {
      services.ollama.enable = true;
    })
    (mkIf cudaEnable.enable {
      environment.systemPackages = with pkgs; [
        cudatoolkit
      ];
      services.ollama.acceleration = "cuda";
    })
  ];
}
