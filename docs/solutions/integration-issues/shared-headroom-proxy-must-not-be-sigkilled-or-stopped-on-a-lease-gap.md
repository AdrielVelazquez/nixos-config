---
title: The shared Headroom proxy must never be SIGKILLed, and must stop only after an idle grace with no live lease
date: 2026-11-01
category: integration-issues
module: packages/headroom-pi.py
problem_type: integration_issue
component: tooling
symptoms:
  - "Pi sessions fail with 'Connection error.' within about 10 ms, and the session file records that same error"
  - "Restarting the failing Pi session restores inference, while the proxy on port 8787 is healthy"
  - "The proxy log shows graceful shutdowns (session summary logged) at the moments sessions broke, not crashes"
root_cause: async_timing
resolution_type: code_fix
severity: high
tags: [pi, headroom, proxy, lease, sigkill, lifecycle, shared-process]
---

# The shared Headroom proxy must never be SIGKILLed, and must stop only after an idle grace with no live lease

One Headroom proxy on port 8787 serves every managed Pi session. Its owner is whichever launcher or project
manager acquired it first, not a single parent. Two lifecycle rules in `packages/headroom-pi.py` broke this:

1. `stop_proxy` sent SIGTERM and then SIGKILL after 5 seconds. A live session could still be using the proxy
   when that happened.
2. The shared manager stopped the proxy the moment the active lease count was zero. A session whose lease had
   been dropped, or was not yet counted, was left pointing at a dead proxy.

A stopped proxy is not visibly "down" from the user's side. The Pi extension in
`dotfiles/pi/extensions/headroom.ts` throws before any network call when the state directory's instance or
manager no longer matches, so the session shows `Connection error.` and only restarting Pi recovers it.

## Fix

- `stop_proxy` sends SIGTERM only and never SIGKILL. A proxy that does not exit in time is left to finish.
- The shared manager stops the proxy only after no lease has been live for `idleSeconds` (default 30), re-checked
  under the lock each time.
- Lease adds and releases are appended to `events.log` in the runtime directory with the reason, so the next
  lost lease is attributable.

## Prevention

- Never add a kill escalation to a process that other sessions can be using. If a stop is needed, it is a
  graceful signal, gated on a live-lease check made under the same lock that registers new leases.
- A session that pins a proxy instance ID cannot survive a proxy restart. Any restart design has to keep the
  instance and port, or let the extension re-read the state, before it can be called recoverable.
- Test the idle grace with `idleSeconds` set to a small value in fixtures, not by removing the grace.

The lost-lease root cause (why a live manager's shared lease disappeared at 21:58) is not yet established;
`events.log` is the instrument for it.
