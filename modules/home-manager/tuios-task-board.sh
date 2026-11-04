#!/usr/bin/env bash
set -euo pipefail

render() {
  local board
  board=$(tuios task ls --all-sessions --json | jq -r -f "$TUIOS_TASK_BOARD_FILTER") || return
  printf '%s\n' "$board"
}

# A failed snapshot clears stale rows; the next event recovers them.
render_or_blank() {
  render || printf '\n'
}

if [[ "${1:-}" == --watch ]]; then
  # Subscribe first: events raised during the initial snapshot wait in the pipe.
  tuios subscribe --types task-claimed,task-finished,task-changed,window-closed,session-created,session-closed \
    | {
      render_or_blank
      while IFS= read -r _event; do
        render_or_blank
      done
    }
else
  render
fi
