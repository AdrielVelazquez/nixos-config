# modules/system/cuda.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.cuda;
in
{
  options.local.cuda.enable = lib.mkEnableOption "Enables CUDA toolkit";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.cudatoolkit ];
  };
}
