# Pi hash-anchored read, edit and grep

`local.pi.hashline.enable` (on by default with `local.pi.enable`) installs the pinned `@deathbeam/pi-hashline@0.0.10`
([source](https://github.com/deathbeam/pi-packages), a fork of `pi-hashline-edit`) through Nix. It overrides Pi's `read`
and `edit` and adds `grep`, so a model edits a file by quoting line anchors instead of reproducing the old text.

## What the model sees

- `read` and `grep` print every line as `LINE#HASH:content`, for example `12#MQQ:const x = 1;`. The hash is three letters of
  `ZPMQVRWSNKTXJBYH`: xxh32 over the line and its two neighbours, the same scheme omp uses (the package vendors omp's MIT code).
  Images, `offset` and `limit` behave as in Pi's native `read`.
- `edit` takes `{ path, edits: [{ op, pos, end?, lines }] }` with `op` one of `replace` (a line or the inclusive span
  `pos`..`end`), `append` and `prepend`. All anchors in one call are validated against one snapshot and applied together, so line
  numbers never shift inside a call.
- A stale anchor is refused with `E_STALE_ANCHOR` and nothing is written; the package recovers only when an older snapshot of the
  file matches and the replayed edit does not conflict with later changes. `E_FILE_CHANGED` refuses a write when the file changed
  between validation and the write. Snapshots live in memory only (8 paths, 4 versions each, 32 MiB).
- A successful edit returns the changed region with fresh anchors, so the next edit needs no re-read of that region.
- Writes go through Pi's file mutation queue, keep CRLF and a BOM, follow symlinks to their target, keep the file mode, and update a
  hard-linked file in place. A temporary `.tmp-<uuid>` file exists in the target directory while a write is in flight.

`grep` is Pi's optional tool and is active in every session that loads the package. It runs `rg`, which the nixpkgs
`pi-coding-agent` wrapper puts on `PATH` (the check runs with no other `rg` on `PATH`).

## Where it applies

| Session | Tools |
|---|---|
| Interactive Pi | hashline `read`/`edit`/`grep`, loaded as a plain `extensions` entry in `settings.json` |
| `build` and `plan` children | the same, through `subagentOnlyExtensions` in their generated role file (`local.pi.routing.writerExtensions`) |
| `scout`, `explore`, `title` children | Pi's native tools: read-only roles gain nothing from anchors and keep their output small |

The entry is deliberately not a required child extension: a required one reaches every role, including the read-only ones.
Children never inherit the parent's extensions, so a child gets hashline only from its own role file.

## Interaction with the rest of the setup

- **Format-on-write** still runs after a hashline `edit` (it needs only `input.path`). Because the formatter rewrites the file, the
  anchors the edit just returned are stale; the note it appends says so, and the model must re-read before the next anchored
  edit. The result order is hashline's own result, the formatter's note, then the LSP diagnostics.
- **`pi-lsp`** reports post-edit diagnostics for a hashline `edit` as for a native one. Its pre-edit baseline reads the changed lines
  from native `oldText` edits only; a hashline edit has none, so the whole file counts as touched [C: `touchedLinesOfEdit`]. That
  widens the set of dependent declarations it re-checks (capped by `pi-lsp`), it never drops diagnostics.
- **`ast_grep_rewrite`** and anything changed through `bash` also invalidate anchors. A mismatch is refused; only the package's
  snapshot recovery can still apply the edit, and only when it proves the replay does not conflict.
- `write` is unchanged: it replaces a whole file and needs no anchors.

## Verification

`checks.x86_64-linux.pi-hashline` drives real Pi with a loopback provider and the real package:

- **mechanics**: read gives anchors on every line; an edit applies and returns fresh anchors; an outside change makes the old
  anchor fail with `E_STALE_ANCHOR` and leaves the file alone; `grep` works with `rg` supplied only by the Pi launcher; CRLF
  bytes, an executable mode and a symlink survive an edit; a valid PNG still reaches the model; `offset`/`limit` return the
  requested lines.
- **interplay**: with format-on-write and the real gopls, one hashline edit returns hashline's result, then gofumpt's note, then
  `declared and not used`, in that order; anchors from before the formatter are refused and a re-read edits again.
- **children**: the real generated `build`, `plan` and `explore` role files launch real children. `build` and `plan` read with
  anchors and `build` edits by anchor; `explore` has no `edit` and reads without anchors. Removing the `subagentOnlyExtensions`
  line makes the check fail.

This proves mechanics, not model behavior. Whether hashline reduces retries or bad edits on your models is not measured here.

## Limits

- The package is young and has one maintainer (first release 2026-09-25, ten releases by 2026-10-10). Its tarball integrity was
  checked against the registry; an upgrade needs the same audit and the `pi-hashline` check.
- It replaces Pi's native `edit` prompt and schema; Pi's `oldText` edit mode is not offered while it is loaded.
- Every read line carries an anchor of about six characters, which adds tokens to each `read`.
- Anything that rewrites a file outside `edit` (the formatter, `ast_grep_rewrite`, `bash`) makes the model's anchors stale, which
  costs a re-read turn. That is the trade for never applying an edit to the wrong lines.
- The TUI rendering of the package's tool cards is covered only by the fullscreen checks (`pi-capabilities-ui`, `pi-omp-parity`),
  which run with this feature enabled.
