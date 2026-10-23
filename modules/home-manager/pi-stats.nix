# modules/home-manager/pi-stats.nix
#
# `pi-stats`: omp's local usage dashboard (`omp stats`, package @oh-my-pi/omp-stats) over Pi's own session logs.
# omp 18.12.6 ingests Pi session JSONL (format v3) unchanged. Only the stats command runs; omp's database and
# native-library cache live under a private HOME so Pi and omp statistics never mix, and Pi's agent directory is
# only read through a symlink to its sessions.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.local.pi.stats;
  launcher = pkgs.writeShellScriptBin "pi-stats" ''
    set -eu
    agent="''${PI_CODING_AGENT_DIR:-${config.local.pi.agentDir}}"
    state="''${XDG_STATE_HOME:-$HOME/.local/state}/pi-stats"
    mkdir -p "$state/home" "$state/agent"
    ln -sfn "$agent/sessions" "$state/agent/sessions"
    HOME="$state/home" PI_CODING_AGENT_DIR="$state/agent" PI_CONFIG_DIR=.omp \
      exec ${lib.getExe' cfg.package "omp"} stats "$@"
  '';
in
{
  options.local.pi.stats = {
    enable = lib.mkEnableOption "pi-stats, omp's usage dashboard over Pi's session logs";
    package = lib.mkOption {
      type = lib.types.package;
      default = config.local.omp.runtime.raw;
      defaultText = lib.literalExpression "config.local.omp.runtime.raw";
      description = "Pinned omp build whose `stats` command is run; reuses the already-built native OMP.";
    };
    launcher = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      default = launcher;
      description = "The generated pi-stats launcher.";
    };
  };
  config = lib.mkIf (config.local.pi.enable && cfg.enable) {
    home.packages = [ cfg.launcher ];
  };
}
