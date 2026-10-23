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
    export default pi => createGhostText(pi, ${builtins.toJSON { wordList = toString cfg.wordList; }});
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
      default = "${wordListPackage}/share/dict/wamerican.35";
      description = "Immutable plain UTF-8 or Latin-1 word list; project settings cannot override it.";
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
