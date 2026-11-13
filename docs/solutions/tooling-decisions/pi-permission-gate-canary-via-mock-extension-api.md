---
title: Pi permission gate is verified by loading the pinned extension under a mock Pi API, and its tool registry must be mocked too
date: 2026-10-29
category: tooling-decisions
module: modules/home-manager/pi/permission.nix
problem_type: tooling_decision
component: tooling
severity: medium
applies_when:
  - "Bumping @gotgenes/pi-permission-system or changing its policy"
  - "A permission canary reports every call blocked, or every call allowed"
  - "Changing extension load order or the required child extension list"
tags: [pi, permissions, canary, fail-closed]
---

# Pi permission gate is verified by loading the pinned extension under a mock Pi API

## Context

`@gotgenes/pi-permission-system` is a `tool_call` gate: it returns `{ block, reason }` or nothing. Its
`pi.getAllTools()` and `pi.getActiveTools()` must exist, or every call fails closed with
"registeredTools is not iterable". The `ctx` must also carry `sessionManager.getSessionDir()`, `getSessionId()` and
`getEntries()`, or session start throws.

## What works

1. Load the packaged `src/index.ts` with `jiti` from Pi's own `node_modules` (Node 24 refuses to strip types under
   `node_modules`).
2. Pass a recursive proxy as `pi`. Record the `on(event, fn)` handlers. Return the tool names from `getAllTools()`.
3. Call `session_start` with a `ctx` where `hasUI` is false. Then call the `tool_call` handler directly with
   `{ toolName, input }`.
4. Read the result: `undefined` or `{}` means allow, `{ block: true }` means deny. For `ask` with no UI, the result
   blocks with "requires approval, but no interactive UI is available".
5. For session-grant checks, set `hasUI: true` and answer `ui.select` with the option label, for example
   "Yes, for this session". The fallback dialog asks the scope question as a second `select`.

## Pitfalls seen

- Print output to a file. A `timeout` kill can drop buffered stdout from a pipe, which looks like a hang.
- The harness calls `process.exit` at its end. A script without it stays alive after the last canary.
- A harness that treats any non-`undefined` result as a block mislabels allows as blocks. Test `res?.block`.

## Outcome

Against `@gotgenes/pi-permission-system` 42.0.0 with the policy in `permission.nix`, deny, allow, fail-closed `ask`,
`bash -c`, `$(...)` and `.env`/`~/.ssh` cases matched the policy. After "Yes, for this session" on `ls -la`, the `rm -rf`
deny, the chained `rm -rf`, `.env`, and `sudo` denies still held. The earlier 41.0.0 shadowing did not reproduce here.

The canary is a throwaway harness under `/tmp`, not a repo check. Persisting it as a `checks/` derivation would make
the result repeatable on every bump.
