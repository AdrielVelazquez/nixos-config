# Pi background jobs

`bash` blocks until a command exits, so a build that takes minutes or a server that never exits holds the whole
conversation. The `job` tool (interactive session only, `local.pi.jobs`) starts a command and returns at once.

| Call | Result |
|---|---|
| `job start {command, name?}` | Runs the command in its own process group in the project directory; returns `#id` and the pid. |
| `job output {id, since?, tail?, wait?}` | What the job printed, stdout and stderr together, and a `cursor`. Pass the cursor as `since` next time to read only what is new. `wait` seconds (at most 120) blocks until there is news or the job ends, so the model checks in instead of polling. |
| `job list` | Every job and its state: `#2 nix build · running 1m 12s`, `#1 npm test · exit 1 after 4s`. |
| `job stop {id}` | SIGTERM to the whole group, SIGKILL after three seconds if anything is left. |

`/jobs` lists the jobs from the prompt and `/jobs stop <id|all>` ends them. The footer counts running jobs (`jobs 2`),
and a job that ends is announced once (`warning` for a non-zero exit, `notifyOnExit`).

## Bounds

Eight jobs run at once (`maxJobs`) and each keeps its newest 1 MiB of output (`maxBufferKiB`); a reader that fell behind is
told how many characters it missed. Jobs run with the user's authority, exactly as `bash` does, so the tool is in the
interactive session only: the read-only roles have no shell and the writer children are short-lived. **Jobs end with the
session** (shutdown, reload or `/new`): the whole process group is killed, and a job that exits as its session is
retired reports to nobody, because touching a retired extension context throws (see
`docs/solutions/integration-issues/pi-extension-callbacks-must-not-touch-a-retired-context.md`).

The `rtk` rewrite applies to `bash`, not to jobs. Output is not secret-scrubbed; do not start a job whose output you
would not show the model.

## Configuration

```nix
local.pi.jobs = {
  enable = true;
  maxJobs = 8;
  maxBufferKiB = 1024;
  notifyOnExit = true;
};
```

`nix build .#checks.x86_64-linux.pi-jobs` runs the manager against real processes (cursor reads, buffer roll-over, group
kill, a command that ignores SIGTERM, the job limit), the tool against a fake Pi, and real Pi through start, a waiting
read, a cursor read and stop, then proves a job left running does not outlive Pi.
