# Pi performance

`just pi-perf` measures two things and prints a table for each; extra arguments go to `tests/pi/perf/startup.py`
(`just pi-perf --runs 3 --only pi-lsp`, `--cold`, `--launcher`).

| Tool | Measures | How |
| --- | --- | --- |
| `tests/pi/perf/startup.py` | What each managed extension adds to starting Pi: CPU seconds, resident memory, wall time to a `get_state` answer | real Pi in RPC mode, a throwaway `HOME` and agent directory, the live settings' extension list; Headroom is never loaded (it starts a proxy) |
| `tests/pi/perf/render.mjs` | What the opencode skin costs per frame on a long transcript | the real components, 200 panels at width 110, CPU time of the first (cold) and the repeated (warm) render |

CPU time and memory are the figures to trust: wall time moves with whatever else the machine is doing. `render.mjs`
takes `--budget-ms` to fail when one warm frame of 200 panels costs more than that.

## What the first measurement found (2026-10-24, Framework)

Measured while about eight Pi sessions of a routing evaluation and their `go build` jobs were running (load average
200 to 400, 59 of 62 GB in use, swap in use), so every wall-clock figure below is indicative and the conclusions rest on
CPU time and memory.

**Every frame redrew everything.** Pi repaints the whole transcript for each frame, and a spinner alone asks for ten a
second. Pi's own components cache their lines; the skin's panels did not. CPU per panel and frame, before and after
memoising each panel on what it shows (`Rows` with a fingerprint, `memoized` for the wrappers around Pi's components):

| Panel | Before | After |
| --- | --- | --- |
| Assistant answer through the skin (Pi's own: 0.007 ms) | 0.292 ms | 0.035 ms |
| `bash` panel, 24-line heredoc | 1.477 ms | 0.001 ms |
| `bash` panel, 60 output lines | 0.297 ms | 0.003 ms |
| `edit` panel, 120-row diff | 0.259 ms | 0.048 ms |

A transcript of 200 panels went from 50 to 300 ms of CPU per frame to 1 to 10 ms. A panel is still laid out when its
width, output, expansion, error state, duration or rewritten command changes (`opencode-ui.test.mjs`).

**Extensions cost little once jiti's compile cache is warm.** jiti transpiles each TypeScript extension (and the
TypeScript inside `node_modules` packages) on first load and keeps the result under the temporary directory, so the
first start after a reboot pays and later starts do not. CPU seconds and memory added to a bare Pi (0.7 to 0.8 s of CPU, 134 MB):

| Extension | Cold cache | Warm cache |
| --- | --- | --- |
| `pi-lsp` | +3.1 s, +193 MB | +0.9 s, +29 MB |
| `pi-subagents` | +3.8 s, +192 MB | +0.7 s, +40 MB |
| `pi-dap` | +2.3 s, +102 MB | +0.3 s, +10 MB |
| `pi-hashline` | +1.3 s, +87 MB | +0.2 s, +6 MB |
| each first-party extension (warm: `opencode-ui` and `todo` measured) | +0.3 to +0.9 s, +28 to +81 MB | −0.1 to +0.1 s, +2 MB |

**Language servers dominate memory once sessions run in parallel.** In the evaluation each Pi process held 90 to 365 MB
(11 processes, 2.7 GB) while its `gopls` held 0.3 to 2.8 GB (16 processes, 8 GB) at 15 to 80 percent of a core. `pi-lsp`
starts a server lazily, on the first request that matches, but never stops one before the session ends. The `gopls`
settings in `modules/home-manager/pi/lsp.nix` also switch on `staticcheck`, `fieldalignment`, `semanticTokens` and every
inlay hint; the model never reads the last two, and the first two cost CPU and memory. Not measured and not changed:
turning them off removes diagnostics the model sees today.

**The `pi` command is the Headroom launcher.** `pi` runs `headroom-pi.py`, which prepares Headroom and then starts Pi, so a
real start is the launcher plus Pi's own session start. One start on the loaded machine took 33 s to a `get_state`
answer, 20.8 s of it in Pi's `createAgentSessionRuntime` (extension loading and every `session_start` handler). That
needs a rerun on a quiet machine with `PI_TIMING=1`, which prints Pi's own breakdown, before anything is blamed.

## Still open, in the order I would take it

1. Re-measure start-up on an idle machine (`just pi-perf --launcher`, then `PI_TIMING=1 pi`) and attribute the launcher,
   MCP connection and `session_start` shares.
2. Stop an idle language server after a few minutes (`pi-lsp` has no such setting; it needs an extension that issues
   `/lsp stop`), and decide whether `staticcheck`, `fieldalignment`, `semanticTokens` and the hints earn their cost
   in agent sessions. Cap `gopls` with `GOMEMLIMIT` if parallel sessions stay common.
3. Precompile the extensions that load from `node_modules` (`pi-lsp`, `pi-subagents`, `pi-dap`, `pi-hashline`) in a
   derivation so the first start after a reboot is as fast as the later ones.
4. Memoise the remaining per-frame work: the inline tool rows and the generic panel for other extensions' tools
   (cheap each, but one per tool call).
