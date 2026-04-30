{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.yazi;

  eml-view = pkgs.writeShellApplication {
    name = "eml-view";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      exec python3 ${./eml-view.py} "$@"
    '';
  };
in
{
  options.local.yazi = {
    enable = lib.mkEnableOption "yazi terminal file manager";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ eml-view ];

    programs.yazi = {
      enable = true;
      shellWrapperName = "yy";

      settings = {
        opener.eml = [
          {
            run = ''${eml-view}/bin/eml-view "$1"'';
            orphan = true;
            desc = "Render .eml in Zen";
          }
        ];

        open.rules = [
          {
            name = "*.eml";
            use = "eml";
          }
          {
            mime = "message/rfc822";
            use = "eml";
          }
        ];
      };
    };
  };
}
