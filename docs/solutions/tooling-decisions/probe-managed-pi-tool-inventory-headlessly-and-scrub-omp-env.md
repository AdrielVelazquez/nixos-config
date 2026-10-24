---
title: Probe the managed Pi's real tool inventory headlessly, and scrub OMP's PI_* variables first
date: 2026-10-23
category: tooling-decisions
module: modules/home-manager/pi.nix
problem_type: tooling_decision
component: tooling
severity: medium
applies_when:
  - "Verifying from an OMP or script shell that managed Pi really exposes a tool, provider or registry operation"
  - "Docs or role allowlists name a capability, such as Tool Registry search, that nobody has listed from a live Pi session"
  - "Running the managed pi wrapper from any shell whose environment was set by OMP"
retire_when: "The managed pi wrapper refuses an inherited OMP agent directory, or Pi ships a documented tool-listing command that needs no model call; read modules/home-manager/pi.nix and run pi --help"
tags: [pi, omp, rpc, tool-inventory, mcp, tool-registry, environment, home-manager]
---

# Probe the managed Pi's real tool inventory headlessly, and scrub OMP's PI_* variables first

## Context
`docs/pi.md` said search comes from "Tool Registry DDG operations" and the Pi role allowlists were built on that. No one had listed the registry from a live session. When a Pi session was asked to search the web it had only `fetch_content`, so the claim had to be tested against a running Pi, not the docs.

Shells started by OMP export `PI_CODING_AGENT_DIR=~/.omp/agent` and `PI_CONFIG_DIR=.omp`. The managed `pi` wrapper keeps a caller-supplied `PI_CODING_AGENT_DIR` (`modules/home-manager/pi.nix` lines 19-22; the `pi-stats` and capability checks rely on that), so a plain `pi` started from such a shell runs against OMP's directory. The OMP wrapper guards the opposite direction (`modules/home-manager/omp.nix` lines 202-217); Pi has no mirror guard.

On 2026-10-23 a first probe made that mistake. Startup printed `Migrated Global commands/ → prompts/`, renamed `~/.omp/agent/commands` to `prompts`, and created empty `auth.json` and `models-store.json` there. Only Pi's built-in `llama` and `mcp` commands loaded, so `/reddit` was absent, which is the visible symptom of the wrong directory. The rename, the two `{}` files and the probe's scratch dir were reverted by hand.

## Guidance
- Start the probe with `PI_*` and `OMP_*` removed from the environment, then set `PI_CODING_AGENT_DIR` to `~/.pi/agent` (the real Nix-managed state, so OAuth and extensions match a normal session) or to a disposable directory. Use a scratch working directory and `--no-session`.
- Run `pi --mode rpc --no-session -e <probe.ts>`, wait 25-30 seconds for background MCP connections, then send `{"type":"prompt","message":"/<command>"}`. Extension commands run without a model call; their `ctx.ui.notify` text arrives as an `extension_ui_request` event with `method: "notify"`.
- The probe extension is one `pi.registerCommand` handler that reads `pi.getAllTools()` (fields `name`, `exposure`, `namespace`, `description`) and notifies a summary. Count by `namespace.name`, and filter names and descriptions for `search|web|ddg|fetch`.
- `/reddit tools` prints registry providers with tool counts in the same way and needs no extension.
- Expect a normal start to rewrite `~/.pi/agent/reddit/preferences.json` and `~/.pi/agent/ghost-text-state.json`; that is ordinary session-start behavior.

## Why This Matters
The probe contradicted the docs. On 2026-10-23 the live registry had providers `atlassian` (151 tools), `echo` (1), `ghe` (35), `glean` (only its `authorize_upstream` sign-in tool), `slack` (27) and `sourcegraph` (9). It had no web or DDG operation, and `fetch_content` was the only web tool among 359. Role allowlists, prompt snippets and docs had pointed the model at search tools that did not exist, which sent it to scrape DuckDuckGo through `fetch_content` and hit a bot check.

A wrong-directory run is quiet. It reports success while mutating the other harness's state, and a missing `/reddit` command is the only hint.

## When to Apply
- Before documenting or allow-listing any capability as "available through" a registry, MCP server or extension.
- Before running `pi` from OMP, a script or a subagent shell.

## Examples
Scrubbed launch (Python, as used for the probe):

```python
env = {k: v for k, v in os.environ.items() if not k.startswith(("PI_", "OMP_"))}
env["PI_CODING_AGENT_DIR"] = os.path.expanduser("~/.pi/agent")
subprocess.Popen(["pi", "--mode", "rpc", "--no-session", "-e", "probe.ts"], cwd=scratch, env=env, ...)
```

Probe command body:

```ts
pi.registerCommand("probe-tools", { description: "list tools", handler: async (_args, ctx) => {
  const tools = pi.getAllTools(), byNs: Record<string, number> = {};
  for (const t of tools) byNs[t.namespace?.name ?? "(none)"] = (byNs[t.namespace?.name ?? "(none)"] ?? 0) + 1;
  ctx.ui.notify(JSON.stringify(byNs), "info");
} });
```

## Related
- `docs/pi.md`, section "Verify or revisit".
- `modules/home-manager/omp.nix`, wrapper guard against inherited Pi scope.
