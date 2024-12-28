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
        function jank_scrollback_search() {
          # Find all files named history.txt in /tmp
          local files=$(find /tmp -name "history.txt" -print0 | xargs -0 stat -c '%Y %n' | sort -rn | head -n 1 | awk '{print $2}')

          # Check if any files were found
          if [[ -z "$files" ]]; then
            echo "No history.txt files found in /tmp" >&2
            return 1
          fi
          local formatted_files=$(echo "$files" | tr '\n' ' ')
          local trimmed_files=$(echo "$files" | tr -d ' \n')

          cat $trimmed_files | fzf
        }

        zle -N jank_scrollback_search

        # Bind the widget to Ctrl+f
        bindkey '^f' jank_scrollback_search
        bindkey "^[[1;3D" backward-word # Alt + Left 
        bindkey "^[[1;3C" forward-word # Alt + Right 
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
