# modules/home-manager/git.nix
# Shared git config + delta integration for adriel-* users.
{
  lib,
  config,
  ...
}:

let
  cfg = config.local.git;
in
{
  options.local.git = {
    enable = lib.mkEnableOption "git config (with delta) for adriel-* users";

    userName = lib.mkOption {
      type = lib.types.str;
      default = "Adriel Velazquez";
      description = "git user.name";
    };

    userEmail = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        git user.email. Leave null on machines that should not bake a personal
        email into the config (e.g. work hosts that have their own gitconfig
        layered on top).
      '';
    };

    extraInsteadOf = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
      default = { };
      description = ''
        Additional `url.<base>.insteadOf` rewrites layered on top of the
        snooguts-only default. Use this to add personal hosts like
        `git@github.com:`.
      '';
      example = {
        "git@github.com:" = {
          insteadOf = "https://github.com/";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    programs.git = {
      enable = true;
      signing.format = null;
      settings = lib.mkMerge [
        {
          user.name = cfg.userName;
          init.defaultBranch = "main";
          push.default = "current";
          pull.rebase = false;
          url = lib.mkMerge [
            {
              "git@github.snooguts.net:" = {
                insteadOf = "https://github.snooguts.net/";
              };
            }
            cfg.extraInsteadOf
          ];
        }
        (lib.mkIf (cfg.userEmail != null) { user.email = cfg.userEmail; })
      ];
    };

    programs.delta = {
      enable = true;
      enableGitIntegration = true;
      options = {
        navigate = true;
        side-by-side = true;
        line-numbers = true;
      };
    };
  };
}
