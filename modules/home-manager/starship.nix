{
  lib,
  config,
  pkgs,
  commands,
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
        character = {
          success_symbol = "[❯](purple)";
          error_symbol = "[❯](red)";
          vimcmd_symbol = "[❮](green)";
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
        git_branch = {
          format = "[$branch]($style)";
          style = "bright-black";
        };
        directory = {
          style = "blue";
        };
        cmd_duration = {
          format = "[$duration]($style) ";
          style = "yellow";
        };
      };
    };
  };
}
