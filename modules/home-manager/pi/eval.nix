{
  config,
  lib,
  pkgs,
  piLib,
  ...
}:
let
  cfg = config.local.pi.eval;
  codemode = config.local.pi.codemode;
  entry = piLib.mkEntry {
    name = "pi-eval.ts";
    module = "eval";
    factory = "createEval";
    args = {
      python = lib.getExe cfg.python.package;
      runner = "${../../../dotfiles/pi/eval}/runner.py";
      inherit (cfg) defaultTimeoutSeconds maxTimeoutSeconds;
      maxOutputBytes = 64 * 1048576;
    };
  };
in
{
  options.local.pi = {
    eval = {
      enable = piLib.mkFeatureEnable "the persistent Python `eval` tool";
      python.package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.python3;
        defaultText = lib.literalExpression "pkgs.python3";
        description = ''
          Interpreter of the kernel, run isolated (`-I`: no PYTHON* variables, no user site-packages). Libraries come
          from this package only; nothing is installed at run time. Use `pkgs.python3.withPackages` to add some.
        '';
      };
      defaultTimeoutSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 120;
        description = "Seconds before a cell is interrupted when the call names no timeout.";
      };
      maxTimeoutSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 3600;
        description = "Upper bound for a call's own timeout.";
      };
      entries = piLib.mkEntriesOption (lib.optionalAttrs cfg.enable { eval = "${entry}"; });
    };
    codemode.enable = piLib.mkFeatureEnable "Pi's native `codemode` tool (sandboxed JavaScript that calls other tools) in the interactive session";
  };
  config = lib.mkIf config.local.pi.enable (
    lib.mkMerge [
      # Interactive session only: the kernel runs arbitrary code with the user's authority, so the entry is
      # deliberately not a required child extension and no role file grants the tool.
      (lib.mkIf cfg.enable { local.pi.extraSettings.extensions = [ cfg.entries.eval ]; })
      # Children already have `codemode` through their role files; this adds it to the interactive session.
      (lib.mkIf codemode.enable { local.pi.extraSettings.defaultTools = [ "+codemode" ]; })
    ]
  );
}
