{
  lib,
  config,
  pkgs,
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
    programs.pay-respects = {
      enable = true;

    };
    programs.fzf = {
      enable = true;
      enableZshIntegration = true;
    };

    programs.zoxide = {
      enable = true;
      options = [ "--cmd cd" ];
      enableZshIntegration = true;
    };
    home.file.".config/oona.jpg".source = config.lib.file.mkOutOfStoreSymlink ./oona.jpg;

    programs.fastfetch = {
      enable = true;
      # settings = {
      #   logo = {
      #     source = "~/.config/oona.jpg";
      #     type = "kitty";
      #   };
      # };
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
        ignoreAllDups = true;
        path = "${config.xdg.dataHome}/zsh/history";
        append = true;
        expireDuplicatesFirst = true;
        share = true;
      };
      initContent = ''
        # s() {
        #   if [[ $# -eq 0 ]]; then
        #     echo "Usage: s <server_address> [ssh_options]"
        #     return 1
        #   fi
        #
        #   local server="$1"
        #   shift
        #   infocmp -x | ssh "$server" "tic -x -" > /dev/null 2>&1
        #
        #   ssh "$server" "$@"
        # }
        # bindkey "''${key[Up]}" up-line-or-search
        # Bind the widget to Ctrl+f
        # bindkey "^[[1;3D" backward-word # Alt + Left 
        # bindkey "^[[1;3C" forward-word # Alt + Right 
        # bindkey "^[[D" backward-word
        # bindkey "^[[C" forward-word
        # bindkey "^[^[[D" backward-word
        # bindkey "^[^[[C" forward-word
        # kitty
        bindkey "\e[1;3D" backward-word # ⌥←
        bindkey "\e[1;3C" forward-word # ⌥→
        eval $(ssh-agent -s)
        ssh-add ~/.ssh/id_ed25519
        eval "$(pay-respects zsh --alias)"
        source <(kubectl completion zsh)
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
