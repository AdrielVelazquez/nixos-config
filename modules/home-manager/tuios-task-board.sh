#!/usr/bin/env bash
set -euo pipefail

tuios task ls --all-sessions --json | jq -r -f "$TUIOS_TASK_BOARD_FILTER"
