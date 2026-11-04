---
title: tuios task cards live in their session, so closing the session's last pane loses them even though pane close and daemon restart keep them
date: 2026-11-04
category: integration-issues
module: modules/home-manager/tuios-task-board.sh
problem_type: integration_issue
component: tooling
symptoms:
  - "A card survives closing one of two panes, and a daemon restart with a pane still open, but disappears after the session's only pane is closed"
  - "tuios task ls --all-sessions no longer lists the card, and task get reports session_not_found"
  - "tuios resurrect lists no saved session, and the session's saved-state directory has no session file"
root_cause: missing_workflow_step
resolution_type: documentation
severity: high
tags: [tuios, task-cards, persistence, sessions, daemon, kanban]
---

# tuios task cards live in their session, so closing the session's last pane loses them even though pane close and daemon restart keep them

## Context

Working out whether a kanban board for agents could survive an accidental pane close or a reboot, we tested on a throwaway
daemon (`tuios --server NAME`), never the live one. Cards are per session, and a session with no panes is not written to
disk. The upstream skill text says cards outlive the pane that added them, which holds for a pane, not for the session.

## Guidance

Verified on tuios 0.12.1 with a `--server` daemon:

- Closing one pane that holds a card keeps the card in its stage, releases the holder, and records `pane closed` in its history.
- `kill-server` followed by `start-server` and `resurrect <session>` restores the session, and its cards with it. A card whose pane was still open comes back unheld, with the reason `restart`.
- Closing the session's only pane, then restarting, drops the session and its cards. `resurrect` finds nothing.

Keep at least one pane open in every session that holds cards. For a board that must survive restarts, do not treat a session
as disposable once its last pane goes. Test persistence with a second pane open; a single-pane test looks like data loss
when the cause is the empty session.

The rail board (`modules/home-manager/tuios-task-board.sh`) shows cards held by no pane in a `doing`, `verify` or `review`
stage as abandoned. Cards claimed by a fan also have no holder by design, so the board can flag them as abandoned falsely.
This was not verified against a real fan.
