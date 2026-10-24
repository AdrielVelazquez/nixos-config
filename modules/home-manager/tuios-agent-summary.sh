#!/usr/bin/env bash
set -euo pipefail

render() {
  local summary
  summary=$(tuios list-agents --all-sessions --json | jq -r -f "$TUIOS_AGENT_SUMMARY_FILTER") || return
  printf '%s\n' "$summary"
}

if [[ "${1:-}" == --watch ]]; then
  # Subscribe before taking the initial snapshot: the ACK means events are
  # already queued, so a state change during that snapshot cannot be missed.
  # Gap markers also cause a fresh snapshot instead of trusting partial events.
  tuios subscribe --types agent-state,window-created,window-closed,session-created,session-closed \
    | while IFS= read -r _event; do
      # A blank line clears stale text, including when there are no agents or
      # a snapshot fails. Keep listening so the next event can recover it.
      if ! render; then
        printf '\n'
      fi
    done
else
  summary=$(render)
  [ -n "$summary" ] || exit 1
  printf '%s\n' "$summary"
fi
