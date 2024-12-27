{
  lib,
  config,
  pkgs,
  commands,
  ...
}:

with lib;

let
  cfg = config.within.zsh;
in
{
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
    home.file.".config/oona.jpg".source = config.lib.file.mkOutOfStoreSymlink ./oona.jpg;

    programs.fastfetch = {
      enable = true;
      # settings = {
      #         logo = {
      #             source = "~/.config/oona.jpg";
      #             type = "kitty";
      #             };
      #     };
    };
    programs.zsh = {
      enable = true;

      # autosuggestion Configuration Options
      autosuggestion.enable = true;
      autosuggestion.strategy = [
        "history"
        "completion"
      ];
      enableCompletion = true;
      syntaxHighlighting.enable = true;
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
        "s" = "ssh";
        "cat" = "bat";
        "ls" = "eza -a";
      };
    };
  };
}
