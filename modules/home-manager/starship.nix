{
  lib,
  config,
  ...
}:

with lib;

let
  cfg = config.within.starship;
in
{
  options.within.starship.enable = mkEnableOption "Enables Starship Settings";

  config = mkIf cfg.enable {
    programs.starship = {
      enable = true;
      settings = {
        format = "$username$hostname$directory$git_branch$git_state$git_status$kubernetes$cmd_duration$line_break$character";

        directory = {
          style = "blue";
        };

        kubernetes = {
          symbol = "☸ "; # Kubernetes symbol plus a space
          # format = "[($user on )($symbol$context)(\($namespace\))]($style) "; # More detailed default example
          format = "[$symbol$context]($style) "; # Simple format: symbol + context name + space
          style = "magenta"; # Choose a color (e.g., magenta)
          disabled = false; # Explicitly enable (though often true by default)
        };

        character = {
          success_symbol = "[❯](purple)";
          error_symbol = "[❯](red)";
          vimcmd_symbol = "[❮](green)";
        };

        git_branch = {
          # Using ''...'' strings here too for consistency with format strings containing $
          format = ''[$branch]($style)'';
          style = "bright-black";
        };

        git_status = {
          # Using ''...'' strings here too
          format = ''[[(*$conflicted$untracked$modified$staged$renamed$deleted)](218) ($ahead_behind$stashed)]($style)'';
          style = "cyan";
          # Ensure zero-width spaces are preserved if they were intentional in TOML
          conflicted = "​";
          untracked = "​";
          modified = "​";
          staged = "​";
          renamed = "​";
          deleted = "​";
          stashed = "≡";
        };

        git_state = {
          # Using ''...'' strings to avoid needing to escape backslashes
          format = ''\([$state( $progress_current/$progress_total)]($style)\) '';
          style = "bright-black";
        };

        cmd_duration = {
          # Using ''...'' strings here too
          format = ''[$duration]($style) '';
          style = "yellow";
        };

      };
      # settings = {
      #   character = {
      #     success_symbol = "[❯](purple)";
      #     error_symbol = "[❯](red)";
      #     vimcmd_symbol = "[❮](green)";
      #   };
      #   git_status = {
      #     format = "[[(*$conflicted$untracked$modified$staged$renamed$deleted)](218) ($ahead_behind$stashed)]($style)";
      #     style = "cyan";
      #     conflicted = "​";
      #     untracked = "​";
      #     modified = "​";
      #     staged = "​";
      #     renamed = "​";
      #     deleted = "​";
      #     stashed = "≡";
      #   };
      #   git_branch = {
      #     format = "[$branch]($style)";
      #     style = "bright-black";
      #   };
      #   directory = {
      #     style = "blue";
      #   };
      #   cmd_duration = {
      #     format = "[$duration]($style) ";
      #     style = "yellow";
      # };
    };
  };
}
