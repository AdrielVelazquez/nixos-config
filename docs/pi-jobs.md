# Pi background jobs

`local.pi.jobs` currently loads the keyboard-navigation test branch of [`pi-background`](https://github.com/AdrielVelazquez/pi-extensions/tree/feat/background-job-navigation),
pinned to an exact fork commit and archive hash through `packages/pi-background.nix`. This is a temporary fork for testing before an upstream PR; see `TODO.md`.
There is no runtime installer or second job manager. It loads only in the parent configuration, not native child roles.

## Commands and tools

| Interface | Purpose |
|---|---|
| `bg_run {command, cwd?, wake_on?}` | Starts a shell command and immediately returns its job ID and log path. Completion automatically resumes idle Pi. |
| `bg_status {id?, lines?}` | Lists jobs, or shows a job's state and recent log lines. |
| `bg_kill {id}` | Stops a background job and its child processes. |
| `/bg` or `/bg bg1` | Opens the interactive job list or a job's live output; Escape closes it. |

The jobs widget shows elapsed time and recent output while work runs. A silent job eventually shows how long it has
produced no output. `wake_on` optionally reports matching output before exit, for example a server's ready line. Use it
for an event that needs action, not every progress line. Completion notifications include the exit status and recent output.

With an empty, focused prompt, press **Down** to select running jobs. **Up/Down** or **j/k** moves through every running job,
including jobs hidden by the compact summary; **Enter** opens its live output and **Escape** returns to the prompt. Typing
also returns to the prompt and preserves that input. If pi-subagents already owns Down, use **Right** to select jobs instead;
its existing Down/Left fleet navigation remains available. Other dialogs and nonempty prompts retain their normal keys.
The live viewer follows the latest output (up to 20 lines), not a full scrollback archive; output combines stdout and stderr.

## Agent behavior

Start builds, full test suites, servers and anything likely to exceed about 30 seconds with `bg_run`. Continue independent
work or end the turn: completion starts a new response without a polling loop. Use `bg_status` when inspecting progress
or results is useful; do not sleep, poll or repeatedly tail a log just to wait for it.
Check a job by its `bg_run` ID with `bg_status`; `bg_wait` takes only subagent run IDs. Bound each job with `timeout <seconds> <cmd>` (plus `set -o pipefail`), because exit is the only default wake-up. For jobs that can fail partway, set `wake_on` to failure output so the agent wakes on the error rather than at exit.

While Pi is already working, completions are steered in before the next model step; they do not interrupt an active tool or
model request. Successful jobs started in the same turn are grouped to avoid one resumed response per result; failures can
wake it before slow siblings finish. Deliberately killed jobs record the result without another automatic response. Processes stop when the session ends.

Managed `AGENTS.md` asks for concise progress updates roughly every 60–90 seconds while actively working, at available
response boundaries. It also asks for bounded tool batches and prompt handling of steering. This is not a hard timer:
backgrounding does not interrupt a model response or an already-running foreground tool.

## Bash timeout semantics

**A managed Bash timeout hands unfinished work to the background; it does not terminate the command.** The plugin also
hands off unexpectedly slow Bash commands after two minutes, and Ctrl+B can move a running command sooner. If another
extension replaces Bash first, this automatic wrapper is not installed; explicit `bg_run` remains the intended path.

Use `bg_kill` when cancellation is required. Do not assume that a timeout, an assistant turn ending, or a returned job ID
means the process stopped. Continue to obtain approval before any command that changes the running system.

## Configuration and migration

```nix
local.pi.jobs.enable = true;
```

The feature defaults on with Pi. Upstream UI settings, if needed, belong in `local.pi.extraSettings.background`, for example
`jobs = "compact"` (alternatives: `"full"`, the default, and `"off"`). Apply configuration through Nix, not a home-directory edit.

The former `job` tool, `/jobs`, cursor-based waiting reads and local implementation are retired. Local-only options
`maxJobs`, `maxBufferKiB` and `notifyOnExit` now report migration errors: they do not configure this upstream plugin.
Do not assume the former eight-job/1-MiB limits still apply.

RTK's automatic rewrite hook applies to Bash, not `bg_run`; keep the explicit `rtk` prefix for background commands.
Command output is not secret-scrubbed, is stored in temporary log files, and its tail is sent to the model on completion.
Only start commands whose output is appropriate for that session. Jobs and their registry are session-owned; log files may
remain after exit, so do not use them as a permanent archive or a secure secret store.

## Verification

`nix build --no-link .#checks.x86_64-linux.pi-jobs` loads the packaged upstream extension in real Pi against a scripted
loopback model. It checks replacement-tool registration, automatic idle resumption, responsiveness during a running job,
same-turn success grouping, prompt failure delivery, parent/child cleanup on cancellation and shutdown, and single-execution
Bash handoff. Nix assertions keep the entry out of required-child and writer-extension lists.

The same check runs the fork's keyboard regression tests against its real extension and shell output using a controlled UI boundary.
Those tests are not proof of terminal rendering or arbitrary extension compatibility. A separate real-Pi PTY smoke test exercised
seven jobs, keyboard selection, live output, `/bg`, clean shutdown, and coexistence with the installed pi-subagents FleetView.
