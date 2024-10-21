{lib, configs, pkgs, ...}:


{
 imports = [
   ./ollama.nix
   ./cuda.nix
 ];
}
