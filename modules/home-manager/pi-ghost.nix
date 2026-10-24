{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.local.pi.ghostText;
  wordListPackage = pkgs.callPackage ../../packages/pi-ghost-wordlist.nix { };
  entry = pkgs.writeText "pi-ghost-text.ts" ''
    import { createGhostText } from "${../../dotfiles/pi/extensions}/ghost-text.ts";
    export default pi => createGhostText(pi, ${
      builtins.toJSON {
        wordList = toString cfg.wordList;
        inherit (cfg) seed;
      }
    });
  '';
in
{
  options.local.pi.ghostText = {
    enable = lib.mkEnableOption "local prose word completion without model requests" // {
      default = true;
      example = false;
    };
    wordList = lib.mkOption {
      type = lib.types.path;
      default = "${wordListPackage}/share/dict/ghost-vocabulary.tsv";
      description = "Immutable vocabulary, one word per line with an optional TAB-separated web frequency (UTF-8 or Latin-1); project settings cannot override it.";
    };
    seed = {
      piSessions = lib.mkEnableOption "learning the typed prompts of earlier Pi sessions (`<agent-dir>/sessions`)";
      ompSessions = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/home/me/.omp/agent/sessions";
        description = "Directory of omp session logs whose typed prompts the engine learns from; null disables it.";
      };
      shellHistory = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "/home/me/.bash_history" ];
        description = "zsh or bash history files; only command names are learned, never arguments.";
      };
    };
    entries = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      internal = true;
      default = lib.optionalAttrs cfg.enable { ghostText = toString entry; };
    };
  };
  config = lib.mkIf (config.local.pi.enable && cfg.enable) {
    # The visual owner installs first; discovery then decorates its final editor.
    local.pi.extraSettings.extensions = lib.mkOrder 1100 [ (toString entry) ];
  };
}
