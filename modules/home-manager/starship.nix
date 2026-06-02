# modules/home-manager/starship.nix
{ lib, config, ... }:

let
  cfg = config.local.starship;
in
{
  options.local.starship.enable = lib.mkEnableOption "Enables Starship prompt";

  config = lib.mkIf cfg.enable {
    programs.zsh.initContent =
      lib.mkIf
        (
          config.programs.starship.enableZshIntegration
          && ((config.programs.starship.settings.right_format or "") == "")
        )
        (
          lib.mkOrder 1050 ''
            # Starship installs RPROMPT even when right_format is empty; blank it so
            # redraws cannot leak the unevaluated command substitution.
            unset RPROMPT RPS1
          ''
        );

    programs.starship = {
      enable = true;
      settings = {
        format = "$username$hostname$directory$git_branch$git_state$git_status$kubernetes$nix_shell$cmd_duration$line_break$character";

        nix_shell = {
          symbol = "❄️ ";
          format = "[$symbol$state( \\($name\\))]($style) ";
          style = "cyan";
        };

        directory.style = "blue";

        kubernetes = {
          symbol = "☸ ";
          format = "[$symbol$context]($style) ";
          style = "magenta";
          disabled = false;
        };

        character = {
          success_symbol = "[❯](purple)";
          error_symbol = "[❯](red)";
          vimcmd_symbol = "[❮](green)";
        };

        git_branch = {
          format = "[$branch]($style)";
          style = "bright-black";
        };

        git_status = {
          format = "[[(*$conflicted$untracked$modified$staged$renamed$deleted)](218) ($ahead_behind$stashed)]($style)";
          style = "cyan";
          conflicted = "​";
          untracked = "​";
          modified = "​";
          staged = "​";
          renamed = "​";
          deleted = "​";
          stashed = "≡";
        };

        git_state = {
          format = ''\([$state( $progress_current/$progress_total)]($style)\) '';
          style = "bright-black";
        };

        cmd_duration = {
          format = "[$duration]($style) ";
          style = "yellow";
        };
      };
    };
  };
}
