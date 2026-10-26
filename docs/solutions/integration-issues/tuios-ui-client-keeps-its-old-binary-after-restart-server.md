---
title: After tuios restart-server the attached UI keeps its old binary, so a new harness reader shows a blank conversation
date: 2026-10-25
category: integration-issues
module: modules/home-manager/tuios.nix
problem_type: integration_issue
component: tooling
symptoms:
  - "The Agents view lists the new harness (here Pi) with its name and idle time, but the conversation pane under the header is empty"
  - "tuios restart-server was run after the Home Manager switch and nothing changed"
  - "The daemon and the agent plugin already run the new build, so the daemon side looks correct"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: medium
retire_when: "Tuios reconnects or restarts the attached UI when the daemon's build differs, so relaunching it after restart-server is no longer needed; check by switching to a new build, running only restart-server and seeing the new reader in the open UI"
tags: [tuios, restart-server, ui-client, deployment, transcript, pi, home-manager]
---

# After tuios restart-server the attached UI keeps its old binary, so a new harness reader shows a blank conversation

## Problem

A Tuios build that adds a transcript reader is deployed through Home Manager, and `tuios restart-server` is run to pick it up. The
Inbox still shows no conversation for the new harness. Three different processes carry a Tuios build, and `restart-server` replaces only one of them.

## Symptoms

- The agent row and header render, with its state and age, but the body under the header is blank.
- `command -v tuios` already resolves to the new store path.
- The daemon process (`tuios daemon`) runs the new store path and started at the time of `restart-server`.

## What Didn't Work

- Running `tuios restart-server` after the switch: it restarts the daemon, and the UI that draws the conversation is not the daemon, so nothing changed.
- Checking the daemon and the installed agent plugin only: both were already on the new build, so they pointed away from the cause.

## Solution

Quit the `tuios` UI in its terminal and start `tuios` again. Panes live in the daemon, so they stay. Then restart any agent
session that started before the new plugin was installed, because a harness loads its plugin when it starts.

To find which process is stale, compare each running binary with the one on `PATH`:

```bash
readlink -f "$(command -v tuios)"
for p in $(pgrep -x tuios); do echo "$p $(readlink /proc/$p/exe) $(ps -o lstart= -p "$p")"; done
```

In the failing case the daemon showed the new store path, and the UI process, which had run for 3.5 days in a kitty window, showed
the old one.

## Why This Works

The daemon reads the transcript, but the UI decides whether to ask for one. It does so from a hard-coded harness list,
`threadTranscriptHarness`, in the tuios repository's `internal/app/inbox_thread.go` (a path in that repo, not this one). A UI built before a harness was added to that list never requests
that harness's transcript, so the thread stays empty even though the daemon would answer. Relaunching the UI loads the new list.

## Prevention

- After a Tuios switch, treat the daemon, the attached UI and each agent harness process as three separate things to refresh.
  The UI needs a quit and relaunch, the daemon needs `restart-server`, and each agent needs a restart to load its plugin.
- When a feature spans the daemon and the UI, check the process binaries before debugging the feature.
- The exception entry for the Pi transcript fork in `TODO.md` repeats this so the next deployment does not rediscover it.

## Related Issues

- `TODO.md`, the `inputs.tuios` entry for `feat/pi-transcript-reader`.
