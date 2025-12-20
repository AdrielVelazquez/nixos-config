# modules/system/cuda.nix
{ lib, config, pkgs, ... }:

let
  cfg = config.within.cuda;
in
{
  options.within.cuda.enable = lib.mkEnableOption "Enables CUDA toolkit";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.cudatoolkit ];
  };
}
