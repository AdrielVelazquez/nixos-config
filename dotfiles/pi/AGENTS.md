# Workflow and project learnings

Use Superpowers for the development workflow. The two CE skills supplement it
with durable project learnings; do not add a second complete workflow pack.

Before related work, consult relevant notes in docs/solutions. If
.compound-engineering/config.yaml defines docs_root, validate that repository-relative
root according to the CE skill and consult its solutions directory instead.

After meaningful verified work and before handoff, invoke ce-compound with
mode:non-interactive depth:lightweight. Save only reusable reasoning not already
clear from code/tests/docs, in the repository's learning directory, never the
installed skill source. Do not record secrets or unrelated personal information.
Use ce-compound-refresh only for requested or relevant stale-note reviews.

# Questions and approvals

Always use the `question` tool whenever you need input, a decision, clarification or permission from the user,
including requests like "can I push these branches?". Never ask in plain text and wait. Tuios only marks a pane as
needing input, and only lists it in the Inbox, when the `question` tool opens its blocking Pi UI prompt; a prose
question alone does not. Offer concrete options, put the recommended one first, and keep the header short (30
characters at most). Do not run system switches, destructive commands, pushes or PR creation without the required
user approval. Repository instructions and explicit user decisions take precedence.

# Pull requests and commits

Do not reply to PR comments unless explicitly asked. Keep feature-branch commits
in logical reversible units, organizing fixups before handoff without discarding
user work. Do not fabricate a commit identity when none is configured.

# Keep AI-generated plans out of Git

Never stage, commit or push AI-generated planning documents, wherever they live:
implementation plans and planning-stage design or specification documents. Treat
`docs/superpowers/` and `docs/plans/` as local-only: never add their contents to Git
or force-add them when ignored. This overrides any skill or workflow instruction to
commit a plan or design. Implementation documentation and verified project learnings
remain allowed. Do not delete tracked planning documents or rewrite history unless asked.

# Evidence

Do not state facts about external software, services, versions, APIs or upstream status from memory when they may
have changed since your training data. Check them with `web_search`, read the primary source (docs, release notes,
README, issue) with `fetch_content`, and cite the URLs you relied on. Before calling something an upstream bug or
claiming it is already fixed, look up the upstream issue, pull request or release. When no source can be found, say
so instead of presenting a recollection as fact.

# Working style

Keep changes consistent with the structure, naming, style and patterns of the surrounding code. Match its
comment density: where the code has none, add none, and comment only behavior the code does not make obvious.

Treat unfamiliar files or changes as potential user work and investigate before deleting or overwriting them. Never
revert, reset or discard changes you did not make. Do not run destructive commands such as `git reset --hard`,
`git checkout --` or recursive deletes on broad paths unless the user clearly asked for that operation; when the
target or scope is unclear, ask first. Prefer non-interactive git commands.

Do not infer authorization for work beyond the user's request. Assumptions that help you make progress are fine while
they stay within the user's intent and the scope of the task. Treat a new message that arrives during work as steering
for the active task, not a replacement; replace the task only when the user clearly cancels it or asks for something
incompatible.

In the final answer, lead with the outcome, not the steps you took to reach it. Use only as much structure as the
answer needs and include technical detail only where it helps.

Do not chain shell commands with separators such as `echo "===="` or `printf '---'`; the output becomes noisy.

# Tools

Pi's native tools are read, write, edit, bash, find and ls, plus the tools added below. Load native
skills by reading their SKILL.md or using /skill:name. Use installed subagent APIs
only when delegation is authorized; do not invent missing harness tools. Track
multi-step work with the `todo` tool. Prefer declarative Nix for
installed behavior and configuration. Prefix shell commands with rtk (a managed hook also rewrites
them for you); use rtk proxy when exact unfiltered diagnostic output is necessary.

Parallel writers on one repository: pass `worktree: true` to `subagent` so each child edits
its own linked worktree and returns a patch handoff to apply deliberately. It needs a clean
git tree (untracked files count) and starts from `HEAD`; when the tree is dirty, run a
single writer instead. Read-only scouts and explorers need no isolation.

Execution: use `eval` for multi-step work where state should persist (parsing, data shaping, loops over tool calls). Its
Python variables survive between calls, `tool.<name>(**args)` calls any other tool, and `read()` returns raw text without
anchors. `bash` runs commands; `codemode` runs sandboxed JavaScript that fans out tool calls. After a compaction or a
kernel-loss notice, run `state()` before using a variable.

Long-running commands (builds, test suites, servers, watchers, `nix build`, anything that may exceed ~30s): start with the
`job` tool, then poll with `job output` using `wait`. Use `bash` only for short commands, and give it a `timeout`.

Editing: when `read` and `grep` print `LINE#HASH:content`, `edit` takes those anchors (`op` replace, append or
prepend, with `pos`, `end` and `lines`). Copy anchors verbatim and batch every change to a file into one call. After a
formatter note, `ast_grep_rewrite` or a `bash` command rewrote the file, re-read it before editing by anchor; an
`E_STALE_ANCHOR` error means re-read, not retry.

Write files with `write` and `edit`, not with shell redirects or heredocs (`cat > file <<EOF`, `tee`, `sed -i`, `echo >`): only those two
show the user a diff, run the formatter and report language-server diagnostics on the result. When a file also needs checking, write it
first and run the check in a separate `bash` call.

Debugging: use the `dap_*` tools with the profiles `go`, `python`, `node`, `native` (Rust, Zig, C: debug a prebuilt
binary with debug info) and `dart`. With `native` (gdb), `dap_evaluate` takes gdb commands: write `print a + b`. If
`dap_launch` answers `running`, call `dap_status` or `dap_stack` before assuming the program ran on. End a runaway
program with `dap_stop`.
