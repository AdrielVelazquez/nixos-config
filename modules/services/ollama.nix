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

  config = mkMerge [
    (mkIf cfg.enable {
      services.ollama.enable = true;
    })
    (mkIf cudaEnable.enable {
      environment.systemPackages = with pkgs; [
        cudatoolkit
      ];
      # CHANGE HERE: explicit acceleration option is removed
      # We now select the specific package build for CUDA
      services.ollama.package = pkgs.ollama-cuda;
    })
  ];
}
