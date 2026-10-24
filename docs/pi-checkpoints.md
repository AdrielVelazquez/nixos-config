# Pi checkpoints

Pi has `/tree` for the conversation and nothing for the files an agent changed. That matters most in a checkout that
already holds uncommitted work, where `git checkout` cannot take the agent's edits back without taking yours. With
`local.pi.checkpoints` a snapshot of the working tree is written before every prompt, and three commands go back.

| Command | What it does |
|---|---|
| `/undo` | Rewinds the last turn: restores the files it changed and returns the conversation to before your last message, whose text comes back in the editor. |
| `/redo` | Undoes the last `/undo`, `/checkpoints` restore or `/tree` restore: the files and, where the conversation moved, the conversation. |
| `/checkpoints` | Lists the branch's snapshots newest first and restores the files to the one you pick; the conversation stays where it is. |

Every restore shows what it will change first (`↺ revert a.txt`, `+ restore sub/b.txt`, `− remove created.txt`) and asks.
It notes when git history moved since the snapshot (`Git moved from abc1234 to def5678`): commits an agent made stay,
only files are restored. The tree as it is now is snapshotted before any restore, which is what `/redo` returns to.
Navigating `/tree` to an earlier point offers to restore the files to match it (`restoreOnTree = "ask"`, the default).
Any new prompt clears the redo.

## What a snapshot holds

Everything `git add -A` would add in the project's work tree (its git top level, or the directory outside git),
honouring `.gitignore`. Ignored files are never read, written or removed by a restore, so build output and `.env` files
stay as they are. Left out on purpose: nested repositories (they are not ours to rewind), files over
`maxFileBytes` (5 MiB), and projects over `maxFiles` (50,000 files; the first snapshot would hash them all, so Pi says
so once and stops checkpointing that session; a flood of new files later is refused the same way). A restore removes files created since the snapshot, brings back deleted
ones and reverts edits, executable bits included.

## Where it lives

Snapshots are commits in a private repository per project under `~/.local/share/pi/checkpoints/<project>-<hash>`,
never in the project's own repository: its index, refs, stash and history are untouched (the check proves it). Each
session has its own index file, so two Pi sessions in one project never collide. Each snapshot is recorded in the
session as a `checkpoint` entry written just before the prompt it precedes, so `/tree` branches and resumed sessions
find the snapshot that belongs to their point in the conversation. Snapshots older than `maxAgeDays` (14) are dropped
when a session starts and git collects the objects an hour later. A snapshot can contain any file you had that git
would add, including an untracked secret: the directory is mode 0700, and `rm -r` of it is always safe.

## Limits

- It restores files, not git: `/undo` after the agent ran `git commit` leaves the commit and reverts the files, so
  `git status` then shows the difference. The dialog warns when this applies.
- Files changed outside the project (`~/.config`, `/etc`) are not covered.
- Ignored files are never snapshotted, so a restore that would destroy one is **refused** with the paths named, and nothing is
  changed: a snapshot with a file at a path where there is now a directory holding ignored files, or a file that grew past the
  size limit since. Move them away and run it again. Everything else a restore removes or overwrites is in the snapshot it
  takes first, which `/redo` brings back.
- A tracked file that grows past `maxFileBytes` leaves the snapshots from then on; the project's own `.git/info/exclude` rules
  are honoured, so a file kept out of git locally stays out of snapshots.
- Native children and the read-only roles never checkpoint; the interactive session's snapshot covers the work its
  `worktree: true` children return.

## Configuration

```nix
local.pi.checkpoints = {
  enable = true;
  maxFiles = 50000;
  maxFileBytes = 5242880;
  maxAgeDays = 14;
  restoreOnTree = "ask"; # or "never"
};
```

`nix build .#checks.x86_64-linux.pi-checkpoints` runs the core against real git, the commands against a fake Pi, and real
Pi in RPC mode through a snapshot, `/undo`, `/redo` and a declined dialog.
