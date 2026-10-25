---
title: Benchmarking Pi measures the wrong thing unless it runs the package binary, and CPU time is the figure that survives a busy machine
date: 2026-10-24
category: tooling-decisions
module: tests/pi/perf
problem_type: tooling_decision
component: tooling
symptoms:
  - "Every start-up measurement of `pi` takes 8 to 15 s and varies by a factor of two between runs"
  - "A throwaway PI_CODING_AGENT_DIR is honoured but the run still starts Headroom and every MCP server"
  - "A skin that looks fast in a short test makes a long session sluggish, with the cost proportional to the number of panels"
root_cause: wrong_measurement_target
resolution_type: process
severity: medium
tags: [pi, performance, benchmarking, jiti, headroom-launcher, render, cpu-time]
---

# Benchmarking Pi measures the wrong thing unless it runs the package binary, and CPU time is the figure that survives a busy machine

## Context

Asked to baseline Pi's performance, the first start-up timings were 8 to 15 s and hung outright under a throwaway
configuration. Three separate causes sat behind that, and each one invalidates a measurement without announcing it.

## Guidance

**Run the package binary, not `pi`.** On this setup `pi` is `headroom-pi.py` wrapped around Pi: it boots a per-project
Headroom proxy (3.5 s when none is running) and only then execs Pi. A benchmark that calls `pi` times the launcher and
starts the proxy and MCP servers as side effects. The package binary is
`$PI_TEST_PACKAGE_DIR/../../bin/pi` (the `*-pi-coding-agent-*` store path); the wrapper only sets `PI_CODING_AGENT_DIR`
when it is unset, so a throwaway agent directory works, but the launcher in front of it does not go away. Time the
launcher on purpose (`startup.py --launcher`), separately, on an idle machine.

**Give each run a shared, warmed `TMPDIR`.** jiti caches the transpiled TypeScript of every extension (and of the
TypeScript inside `node_modules` packages) under the temporary directory. A fresh `TMPDIR` per run measures the cold
cache: each extension then looks like +0.3 s and +35 MB, and `pi-lsp`, `pi-subagents`, `pi-dap` and `pi-hashline`
look like 1 to 4 s. Warm, they are 0.0 to 0.9 s. Report both, say which is which, and note that the first start after a
reboot pays the cold cost.

**Use CPU time and resident memory, not wall time, when the machine is shared.** The measurements ran during a routing
evaluation (load average 200 to 400, swap in use): wall times were meaningless and CPU seconds and RSS still ordered the
extensions correctly. Check `uptime` and `ps --sort=-rss` before trusting any wall figure, and rerun the wall-clock part
when the load has gone. Those same `ps` lines also showed the real memory story: a `gopls` per Pi session
(0.3 to 2.8 GB each) dwarfed the Pi processes themselves.

**Measure the per-frame cost of anything that draws, with the whole transcript.** Pi repaints every component on every
frame (a spinner alone asks for ten a second), and its own components cache their lines. A renderer that rebuilds from
scratch looks free at one panel and costs 50 to 300 ms of CPU per frame at 200. `tests/pi/perf/render.mjs` measures
cold and warm CPU per panel; the fix is a fingerprint of everything the build reads besides the width, returning the last
lines while it is unchanged, plus an identity check on the lines Pi hands a wrapper.

## Why it matters

Each of these produces a plausible number. Hung runs were explained as "Pi is slow", the cold-cache table as
"extensions are expensive", and the busy-machine wall times as "the launcher is slow", and any of them would have sent
the optimisation effort to the wrong place. The real costs were the per-project Headroom proxy, the first start after a
reboot, language servers per parallel session, and a skin that drew everything again each frame.

## When to apply

Before quoting or acting on any Pi timing: name the binary, the cache state, the machine load and the metric. Two
practical traps from the same session: `pkill -f <pattern>` kills the shell running it when the pattern appears in the
command line (write it as `[p]attern`), and `pkill -x pi` risks the Pi session you are working in.

## Related

- `docs/pi-performance.md` for the measurements and the ranked follow-ups
- `docs/solutions/tooling-decisions/probe-managed-pi-tool-inventory-headlessly-and-scrub-omp-env.md` for the other
  reason a throwaway Pi run touches the real configuration
