{ lib, config, pkgs, ... }:

with lib;

let cfg = config.within.kitty;
in {
  options.within.kitty.enable = mkEnableOption "Enables Kitty Terminal Settings";

  config = mkIf cfg.enable {
    home.packages = [ pkgs.kitty ];
    programs.kitty.enable = true;
    # programs.kitty.themeFile = "ChalkBoard";
    programs.kitty.shellIntegration.enableZshIntegration = true;
    programs.kitty.settings = {
        scrollback_pager_history_size = 60;
        font_family = "GoMono Nerd Font";
        font_size = "16.0";
        tab_bar_edge = "top";
        tab_bar_style = "slant";
	# Allow Remote
	# Following Plugins that require remote control
	# kitty-scrollback.nvim
	allow_remote_control = "socket-only";
	# Required for Kitty Scrollback
	listen_on = "unix:/tmp/kitty";

  	shell_integration = "enabled";
	# Mapping to use nvim as my scrollback scrollback_pager_history
	editor = "nvim";
	# kitty-scrollback.nvim Kitten alias
	action_alias = "kitty_scrollback_nvim kitten $HOME/.local/share/nvim/lazy/kitty-scrollback.nvim/python/kitty_scrollback_nvim.py";
      };
    programs.kitty.keybindings = {
      "ctrl+shift+f" = "launch --type=overlay --stdin-source=@screen_scrollback /bin/sh -c \"~/.fzf/bin/fzf --no-sort --no-mouse --exact -i --tac | kitty +kitten clipboard\"";
      "kitty_mod+h" = "kitty_scrollback_nvim";
      "kitty_mod+g" = " kitty_scrollback_nvim --config ksb_builtin_last_cmd_output";
      "ctrl+f" =  "launch --type=overlay /bin/sh -c 'find . -type d -not -path \"*/.git/*\" | /usr/local/bin/fzf | kitty +kitten clipboard'";
    };
  };
}
