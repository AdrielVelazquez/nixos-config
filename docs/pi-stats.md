# pi-stats

`pi-stats` runs omp's local usage dashboard (`omp stats`, package `@oh-my-pi/omp-stats`) over **Pi's own** session logs.
It exists because omp's README lists `omp-stats` as a standalone package, and omp 18.12.6 ingests Pi's session JSONL
(format v3) unchanged: a Pi session of four turns was imported with its tokens, cache rate and cost (`checks.pi-stats`).

## Use

```sh
pi-stats                 # start (or reuse) the dashboard on http://127.0.0.1:3847 and open it
pi-stats --summary       # console summary
pi-stats --summary --json
pi-stats --port 4000
```

All `omp stats` flags work. Enable with `local.pi.stats.enable = true;` (needs `local.pi.enable`).

## How it stays out of the way

- Sessions are read from `$PI_CODING_AGENT_DIR/sessions` (default `~/.pi/agent/sessions`) through a symlink in a private
  agent directory, `${XDG_STATE_HOME:-~/.local/state}/pi-stats/agent`. Pi's agent directory is never written.
- omp's stats database (`.omp/stats.db`) and its native-library cache live under `.../pi-stats/home`, so Pi statistics
  never mix with the real `~/.omp` used by omp itself.
- The package is the already-built OMP from `config.local.omp.runtime.raw`; no extra build.
- The private HOME has no omp credentials or provider configuration, so omp's optional frustration judging cannot call a model.

## Limits

Statistics reflect whatever Pi recorded: cost depends on the model prices in Pi's catalog, and sessions of the `roles/auto`
virtual model are attributed to the physical models that answered (Pi records the dispatched model on each message).

## Verify

`rtk nix build --no-link .#checks.x86_64-linux.pi-stats` imports `tests/pi/fixtures/stats-session.jsonl` and asserts four
requests, 11,700 input tokens, model `unit`, an untouched agent directory and a private database.
