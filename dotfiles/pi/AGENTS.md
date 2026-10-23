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

Always use the question tool when input, clarification or permission is needed.
Use concrete choices with the recommended choice first. Blocking Pi UI prompts
let Tuios report needs-input; a prose question alone does not. Do not run system
switches, destructive commands, pushes or PR creation without the required user
approval. Repository instructions and explicit user decisions take precedence.

# Pull requests and commits

Do not reply to PR comments unless explicitly asked. Keep feature-branch commits
in logical reversible units, organizing fixups before handoff without discarding
user work. Do not fabricate a commit identity when none is configured.

# Tools

Pi's native tools are read, write, edit, bash and optional grep/find/ls. Load native
skills by reading their SKILL.md or using /skill:name. Use installed subagent APIs
only when delegation is authorized; do not invent missing harness tools. Track
tasks in plan files when no dedicated task tool exists. Prefer declarative Nix for
installed behavior and configuration. Prefix shell commands with rtk; use rtk proxy
when exact unfiltered diagnostic output is necessary.

Parallel writers on one repository: pass `worktree: true` to `subagent` so each child edits
its own linked worktree and returns a patch handoff to apply deliberately. It needs a clean
git tree (untracked files count) and starts from `HEAD`; when the tree is dirty, run a
single writer instead. Read-only scouts and explorers need no isolation.

Debugging: use the `dap_*` tools with the profiles `go`, `python`, `node`, `native` (Rust, Zig, C: debug a prebuilt
binary with debug info) and `dart`. With `native` (gdb), `dap_evaluate` takes gdb commands: write `print a + b`. If
`dap_launch` answers `running`, call `dap_status` or `dap_stack` before assuming the program ran on. End a runaway
program with `dap_stop`.
