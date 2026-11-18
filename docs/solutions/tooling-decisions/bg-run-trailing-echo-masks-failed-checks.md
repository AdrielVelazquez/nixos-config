---
title: Background jobs report their last command's exit status, so a trailing echo hides a failed check
date: 2026-11-18
category: tooling-decisions
module: bg_run verification commands
problem_type: tooling_decision
component: tooling
severity: medium
applies_when:
  - "Starting a nix build, check, or eval through bg_run and reading its exit status"
  - "Writing a verification job that pipes output through tail, grep or head"
retire_when: "bg_run reports the status of the failed command in a pipeline, or verification jobs stop needing a trailing marker"
tags: [bg-run, verification, exit-status, nix-build, pi-checks]
---

# Background jobs report their last command's exit status, so a trailing echo hides a failed check

## Context

While verifying the Daybreak Blue alias, `checks.pi-headroom-providers` exited 1 on a Gemini route assertion. The background job still reported `exit 0`. Its command ended with `nix build ... | tail -40; echo "VERIFY_DONE"`, so the job's status was the status of `echo`. The failure only showed because the log was read. Earlier jobs had the same shape.

## Guidance

- Print each checked command's own status inside the job, after its pipe: `cmd | tail -40; echo "CHECK_EXIT=${PIPESTATUS[0]}"`. Read the echoed value.
- Or end the job with the checked command, under `bash -o pipefail -c '...'`, so the job's status is the build's.
- Confirm success from the echoed exit code or a success marker in the log (for example `PASS:`), not from the job's `exit 0` alone.

## Applicability

Applies to `bg_run` jobs and any shell command that pipes a build, test or eval through `tail`, `grep` or `head`. Verified on this host: `/bin/sh` is bash, and `set -o pipefail` returns 1 for a failing pipe, so the option is not the problem. The trailing command is.
