{lib, configs, pkgs, ...}:


{
 imports = [
   ./kitty.nix
   ./neovim.nix
   ./nixvim.nix
   ./nixvim/config/default.nix
 ];
}
