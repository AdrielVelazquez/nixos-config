---
title: A Pi extension callback that fires as its session ends throws on the captured context and exits Pi with code 1
date: 2026-10-24
last_updated: 2026-10-29
category: integration-issues
module: modules/home-manager/pi/jobs.nix
problem_type: integration_issue
component: tooling
symptoms:
  - "Pi exits with status 1 and prints 'This extension ctx is stale after session replacement or reload' with a stack through ExtensionRunner.assertActive and get hasUI"
  - "The run itself finished and every event was emitted; only the exit code and stderr are wrong"
  - "Only a callback that runs after session_shutdown triggers it, here a job killed by the shutdown handler whose exit callback read ctx.hasUI"
root_cause: async_timing
resolution_type: code_fix
severity: medium
tags: [pi, extensions, session-shutdown, ctx, async, jobs, unhandled-rejection]
---

# A Pi extension callback that fires as its session ends throws on the captured context and exits Pi with code 1

The local job extension described here was retired on 2026-10-29 in favor of unmodified upstream `pi-background`
(`docs/pi-jobs.md`). This is a historical diagnosis and a reusable lifecycle rule, not a patch carried in that package.

## Problem

An extension keeps the `ctx` it was handed and uses it later from a callback: a child process exit, a timer, a promise
continuation. Once the session is replaced, reloaded or shut down, Pi retires that context, and its getters
(`ctx.hasUI`, and the methods behind `ctx.ui`) call `assertActive()` and throw. The `job` extension killed its
processes in `session_shutdown`; each process's `close` event then ran an exit callback that read `ctx.hasUI`. The throw
happened inside a promise `.then`, so it was an unhandled rejection and Node ended Pi with exit code 1, after the model
run had completed. Print and JSON mode were the visible case: a scripted check saw `returncode 1` with a correct event
stream, which looks like a harness problem until the stack names `assertActive`.

## Guidance

- Treat a captured `ctx` as valid only until `session_shutdown` is handled. Clear your reference in that handler, before
  anything you start cleaning up can call back.
- Make every callback that outlives the handler that created it best effort: read the context inside a `try` and swallow
  the throw. There is nobody left to tell, so dropping the message is correct.
- When shutdown kills work whose completion you would normally announce, detach the announcing callback first (`onExit =
  undefined`) and then kill, so the order of events cannot reach a retired context.
- `hasUI` is a getter that asserts, not a plain boolean: `if (current?.hasUI)` is already a use of the context.

```ts
const report = (action: (ctx: ExtensionContext) => void) => {
  if (!current) return;
  try {
    if (current.hasUI) action(current);
  } catch {
    // The session is gone; there is nobody to tell.
  }
};
pi.on("session_shutdown", () => {
  manager.onExit = undefined; // before stopAll(), which makes the callbacks fire
  manager.stopAll();
  current = undefined;
});
```

## Applies when

An extension holds a context beyond the event handler that received it and has anything asynchronous that can complete
during shutdown (processes, sockets, timers, watchers). The original local manager's stale-context unit test was retired
with that implementation. Its replacement check, `tests/pi/jobs-session.py` (`checks.pi-jobs`), loads the packaged upstream
extension in real Pi and checks that shutdown stops running parent/child processes without a stale-context error.
