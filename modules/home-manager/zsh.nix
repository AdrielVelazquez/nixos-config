# modules/home-manager/zsh.nix
# ZSH shell configuration
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.within.zsh;
  kubectlEnabled = config.within.kubectl.enable or false;
in
{
  options.within.zsh.enable = lib.mkEnableOption "Enables ZSH Settings";

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      fastfetch
      eza
      bat
    ];

    programs.pay-respects.enable = true;

    programs.fzf = {
      enable = true;
      enableZshIntegration = true;
    };

    programs.zoxide = {
      enable = true;
      options = [ "--cmd cd" ];
      enableZshIntegration = true;
    };

    programs.direnv = {
      enable = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };

    programs.fastfetch.enable = true;

    home.file.".config/oona.jpg".source = config.lib.file.mkOutOfStoreSymlink ./oona.jpg;

    programs.zsh = {
      enable = true;

      # Autosuggestion Configuration
      autosuggestion = {
        enable = true;
        strategy = [
          "history"
          "completion"
        ];
      };

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

      initContent = lib.mkMerge [
        # Base keybindings and shell setup
        ''
          # Kitty keybindings
          bindkey "\e[1;3D" backward-word # ⌥←
          bindkey "\e[1;3C" forward-word # ⌥→

          # Pay respects
          eval "$(pay-respects zsh --alias)"

          # Just command completion
          eval "$(just --completions zsh)"

          # Fastfetch on shell start
          fastfetch
        ''

        # Kubectl completion (only if kubectl is enabled)
        (lib.mkIf kubectlEnabled ''
          source <(kubectl completion zsh)
        '')
      ];

      shellAliases = {
        "s" = "kitten ssh";
        "cat" = "bat";
        "ls" = "eza -a";
      };
    };
  };
}
