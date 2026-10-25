# Pi performance

`just pi-perf` measures two things and prints a table for each; extra arguments go to `tests/pi/perf/startup.py`
(`just pi-perf --runs 3 --only pi-lsp`, `--cold`, `--launcher`).

| Tool | Measures | How |
| --- | --- | --- |
| `tests/pi/perf/startup.py` | What each managed extension adds to starting Pi: CPU seconds, resident memory, wall time to a `get_state` answer | real Pi in RPC mode, a throwaway `HOME` and agent directory, the live settings' extension list; Headroom is never loaded (it starts a proxy) |
| `tests/pi/perf/render.mjs` | What the opencode skin costs per frame on a long transcript | the real components, 200 panels at width 110, CPU time of the first (cold) and the repeated (warm) render |

Run it on an idle machine for wall time; CPU time and memory hold up under load. `render.mjs`
takes `--budget-ms` to fail when one warm frame of 200 panels costs more than that.

## What the measurements found (2026-10-24, Framework)

Two sessions of measuring. The first ran while about eight Pi sessions of a routing evaluation and their `go build` jobs
kept the machine at load average 200 to 400 (59 of 62 GB in use, swap in use), so it rests on CPU time and memory.
The second ran on an idle machine (load under 6) and supplies the wall-clock figures.

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

**Most of a start is the Headroom launcher, not Pi.** On the idle machine Pi with every extension that starts without
Headroom (20 of them) answers `get_state` in 1.6 s (bare Pi 0.5 s; `pi-lsp` adds 0.4 s, `pi-subagents` 0.2 s, the rest are
inside the noise of 0.1 s) and holds 214 MB (bare 136 MB). Through the `pi` command, which is `headroom-pi.py` followed by
Pi, the same answer took:

| Start | Time to `get_state` |
| --- | --- |
| first session in a project root, no Headroom proxy yet | 5.2 to 5.9 s |
| a second session while the first is open (proxy reused) | 2.0 to 3.4 s |
| a new session three seconds after the last one closed | 2.4 s |

`PI_TIMING=1` puts Pi's own session start at 1.09 s of that (all extension imports together about 0.2 s), so the first
session in a project spends about 3.5 s waiting for a per-project Headroom proxy to boot and about a second more in the
launcher itself. Every linked worktree is a new project root, so a batch of worktree sessions (the evaluation above) boots
a proxy each; 41 `.headroom-wrapped` processes held 2.2 GB while it ran.

## Still open, in the order I would take it

1. Shorten the first start in a project root: keep the Headroom proxy for a grace period after its last lease ends, and
   start Pi while the proxy boots instead of after it (`packages/headroom-pi.py` `acquire`/`manage`; the Headroom
   extension already fails closed until the proxy answers). Re-measure with the table above.
2. Stop an idle language server after a few minutes (`pi-lsp` has no such setting; it needs an extension that issues
   `/lsp stop`), and decide whether `staticcheck`, `fieldalignment`, `semanticTokens` and the hints earn their cost
   in agent sessions. Cap `gopls` with `GOMEMLIMIT` if parallel sessions stay common.
3. Precompile the extensions that load from `node_modules` (`pi-lsp`, `pi-subagents`, `pi-dap`, `pi-hashline`) in a
   derivation so the first start after a reboot is as fast as the later ones.
4. Memoise the remaining per-frame work: the inline tool rows and the generic panel for other extensions' tools
   (cheap each, but one per tool call).
