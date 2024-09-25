
{ lib, config, pkgs, commands, ... }:

with lib;

let cfg = config.within.kitty;
in {
  options.within.zsh.enable = mkEnableOption "Enables ZSH Settings";

  config = mkIf cfg.enable {
    home.packages = [
        pkgs.fastfetch
        pkgs.eza
        pkgs.bat

    ];
    programs.fzf = {
            enable = true;
            enableZshIntegration = true;
    };
    programs.fastfetch = {
            enable = true;
        };
    programs.zsh= {
        enable = true;

        # autosuggestion Configuration Options
        autosuggestion.enable = true;
        autosuggestion.strategy = ["history" "completion"];
        enableCompletion = true;
        syntaxHighlighting.enable = true;
        envExtra = ''
            export SOMETHING="adriel"
        '';
        history = {
            size = 50000;
            save = 50000;
            path = "${config.xdg.dataHome}/zsh/history";
            append = true;
            expireDuplicatesFirst = true;
            share = true;
        };
        initExtra = ''
        fastfetch
        '';
        shellAliases = {
                "s" = "kitten ssh";
                "cat" = "bat";
                "ls" = "eza -a";
            };
    };
};
}
