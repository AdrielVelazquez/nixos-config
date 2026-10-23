# checks/pi-stats.nix
#
# `pi-stats` runs omp's real `omp stats` over Pi's own session JSONL in a Nix sandbox.
{
  lib,
  pkgs,
  homeConfigurations,
  ...
}:
let
  base = homeConfigurations.cachyos-framework13;
  stats =
    (base.extendModules {
      modules = [
        {
          local.pi.enable = lib.mkForce true;
          local.pi.stats.enable = lib.mkForce true;
        }
      ];
    }).config;
  launcher = stats.local.pi.stats.launcher;
in
{
  pi-stats =
    pkgs.runCommand "pi-stats-check"
      {
        nativeBuildInputs = [ pkgs.jq ];
      }
      ''
        export HOME="$TMPDIR/home" XDG_STATE_HOME="$TMPDIR/state"
        mkdir -p "$HOME" "$TMPDIR/agent/sessions/--fixture--"
        cp ${../tests/pi/fixtures/stats-session.jsonl} \
          "$TMPDIR/agent/sessions/--fixture--/2026-10-23T00-00-00-000Z_fixture.jsonl"
        PI_CODING_AGENT_DIR="$TMPDIR/agent" ${launcher}/bin/pi-stats --summary --json \
          > "$TMPDIR/out.json" 2> "$TMPDIR/err.txt" || { cat "$TMPDIR/err.txt"; exit 1; }
        jq -e '.overall.totalRequests == 4 and .overall.totalInputTokens == 11700 and .byModel[0].model == "unit"' \
          "$TMPDIR/out.json"
        # Pi's agent directory is only read; omp keeps its own state under the private state dir.
        test "$(find "$TMPDIR/agent" -mindepth 1 -maxdepth 1 | wc -l)" = 1
        test -f "$XDG_STATE_HOME/pi-stats/home/.omp/stats.db"
        touch "$out"
      '';
}
