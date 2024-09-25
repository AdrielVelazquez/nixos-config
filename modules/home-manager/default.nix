{lib, configs, pkgs, ...}:


{
 imports = [
   ./kitty.nix
   ./neovim.nix
   ./zsh.nix
   ./starship.nix
   # ./nixvim.nix
 ];
}
