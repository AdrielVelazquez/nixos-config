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
needing input, and only lists it in the Inbox, when the `question` tool opens its blocking prompt; a prose
question alone does not. Offer concrete options, put the recommended one first, and keep the header short (30
characters at most). Do not run system switches, destructive commands, pushes or PR creation without the required
user approval. Repository instructions and explicit user decisions take precedence.

# Task board

Inside a tuios pane (`$TUIOS_PANE_ID` is set), the session's task board tracks the work. Change it only with `tuios task`.

- Before starting, run `tuios task ls --open`. If a card covers your work, claim it with `tuios task claim <id>`. Otherwise add one with `tuios task add -p '<what to do>' '<title>'`, then claim it.
- Cards shown as abandoned on the board have no holder and were left by an earlier pane. Resume them before starting new work: claim, then continue.
- Keep the card current: `tuios task stage <id> verify` or `review` when the work moves on, `tuios task block <id> <reason>` when stuck, and `tuios task block <id> --clear` once the block lifts.
- Finish with `tuios task done <id>`. If you must stop first, run `tuios task release <id>` and leave the next step with `tuios note set "<next step>"`.
- Do not claim a card another pane holds (`task_held`), or change a card you do not hold, unless the person asks.

# Pull requests and commits

Do not reply to PR comments unless explicitly asked. Keep feature-branch commits
in logical reversible units, organizing fixups before handoff without discarding
user work. Do not fabricate a commit identity when none is configured.
When mentioning a specific commit, PR, or line of code, give the exact link to that commit, PR, or line (for example a GitHub permalink with the full commit SHA or `#L<start>-L<end>`), not just a bare hash, number, or path.

# Commit History

When working against a feature branch (not main or master), organize the commits and rebase them so that each
commit is one logical unit of work. Do not leave nine commits of small fixes: for example, all changes within one
package or directory belong in one commit, so it can be reverted cleanly. Do this in every situation, so reviewers can
follow the change through the commit history.

# Keep AI-generated plans out of Git

Never stage, commit or push AI-generated planning documents, wherever they live:
implementation plans and planning-stage design or specification documents. Treat
`docs/superpowers/` and `docs/plans/` as local-only: never add their contents to Git
or force-add them when ignored. This overrides any skill or workflow instruction to
commit a plan or design. Implementation documentation and verified project learnings
remain allowed. Do not delete tracked planning documents or rewrite history unless asked.

# Evidence

Do not state facts about external software, services, versions, APIs or upstream status from memory when they may
have changed since your training data. For public research, check them with `websearch`, read the primary source
(docs, release notes, README, issue) with `webfetch`, and cite the URLs you relied on. Before calling something
an upstream bug or claiming it is already fixed, look up the upstream issue, pull request or release. When no source
can be found, say so instead of presenting a recollection as fact.

If you are unfamiliar with something, or cannot confirm a fact, verify it with the appropriate available tools before
answering; use `websearch` for public research. For private or internal resources, use authorized repository tools,
MCP integrations or host-qualified CLIs. Do not send private contents or sensitive search terms to public search or
fetch services. Say so when the available checks cannot confirm the fact.

When naming a version, release or tag, first check the ref type: `git ls-remote --tags <repo>` or `gh release view <tag> --repo <owner/repo>`. Do not call something a release, or say it is not one, without that check.

Separate what you verified from what you did not in the final answer, and close gaps that one command would settle before reporting them as unknown.

# Discover tools before declaring limits

Before guessing, asking the user to retrieve information, or saying you cannot
access something, discover relevant tools, including deferred MCP operations.
Read their schemas and use the most appropriate authorized read-only capability.

Match the tool to the resource's actual host and scope. A public fetch hitting
a login page, or a tool querying the wrong host and returning 404, does not
establish that the resource is inaccessible. Try an available authenticated
integration or host-qualified CLI before reporting an access limitation.

For repository-specific questions, inspect the relevant files and implementation
before answering. Do not substitute general knowledge or a conditional answer
for an available check.

Use targeted fallbacks, not exhaustive retries. If access remains blocked,
state what you tried, the specific failure, and what remains unverified.
Tool availability does not authorize writes or bypassing access controls.

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

Read files with `read`, which returns `LINE#HASH:content` rows. Change existing files only with the anchored tools:
`replace` (a line range, by `startAnchor` and optional `endAnchor`), `replace_match` (one literal match), `insert` (after
an anchor), `copy` and `move` (with `destFile`), and `undo_last_change`. Find anchors with `anchor_grep`. Take the anchors
from the latest `read` or `anchor_grep` result, copy them verbatim, and batch the edits for one file into one call. If an
anchor reports `E_ANCHOR_STALE` or the file reports `E_FILE_CHANGED`, read the file again instead of retrying the same
anchors. The built-in `edit` and `apply_patch` are disabled in this project.

Use `write` only to create new files, not with shell redirects or heredocs (`cat > file <<EOF`, `tee`, `sed -i`,
`echo >`), because those bypass the anchored tools.

Structural code search uses `ast-grep_ast_grep_search` (a `pattern`, optionally `lang` and `paths`), `ast-grep_ast_grep_scan` (rules
or a config) and `ast-grep_ast_grep_test`. A rewrite requires an explicit `apply` value: preview with `apply` false, show the
result, and only then rerun the same call with `apply` true.

`ipython_execute` runs Python in a named session (`session` and `code`), and variables persist between calls in that session.
Use `ipython_list_sessions`, `ipython_reset`, `ipython_interrupt` and `ipython_shutdown` to manage sessions. Use it for
multi-step data work where state should persist, not for shell tasks that `bash` handles.

Run long commands (builds, test suites, servers, watchers, anything that may exceed about 30 seconds) with the shell
tool's `background` option; completion notifies the session, so continue working instead of sleeping or polling. Give
every command a timeout, for example `timeout 600 <command>`. Shell commands are rewritten through rtk automatically
for compact output; use `rtk proxy <cmd>` when exact unfiltered output is necessary.

Track multi-step work with the built-in todo list and keep it current. Ask the user through `question`. Prefer
declarative Nix for installed behavior and configuration.

Load a skill when a task matches it. Delegate to subagents only when the user has authorized delegation.

# Model routing and subagents

Route each task to the cheapest model that can do it well, and escalate only on evidence. Cost is dominated by
context re-sent each turn, so keep the main session for decisions and edits, and delegate bounded work.

Agents (models are set in Nix through `local.opencode.routing.agents`):
- `explore`, `scout` and `title`: low-cost tier for reading, searching, summarizing and titles. `scout` is a read-only research subagent. Never ask these agents to write.
- `build`: low-cost implementation tier.
- `plan`: strong tier for design and sequencing.

Rules:
1. Delegate read-heavy and bounded work to read-only agents such as `scout` or `explore`. Keep edits, decisions and user communication in the main session.
2. Write child briefs that stand alone: goal, files, constraints and the expected output. Children start with fresh context and cannot see this session.
3. Start at the cheapest tier that fits. Escalate one tier only when verification fails, and say why.
4. Use extra reasoning only when the task needs it, such as planning, review or a final gate on security or data-loss risk.
5. Do not switch models mid-session to save money: a new model usually starts with a cold prompt cache. Choose the model at session start, and use a child for work that needs a different model.
6. Verify a child's claims before reporting them. Children report; the parent decides and says what was verified.

# Responsiveness

While actively working, aim for a concise progress update every 60 to 90 seconds and at significant milestones: what
changed, what is running, and what comes next. These are best-effort updates at response boundaries, not a timer.
Avoid repetitive "still waiting" messages and avoid extra calls made only to show activity.

State the expected duration when you start a long command. When it runs well past that, check its output, stop it and
investigate instead of waiting indefinitely, and report the blocker. Do not sleep or poll inside a command unless the
user explicitly asked for that.

# Debugging

Debug with the `dap_debug_*` tools. `dap_debug_launch` takes `program`, `cwd` and `adapter` (`debugpy`) and returns a
`session_id`; pass that `session_id` to every later call. Set breakpoints with `dap_debug_set_breakpoints`, then use
`dap_debug_continue`, `dap_debug_step_over`, `dap_debug_step_into` or `dap_debug_step_out`. Inspect with
`dap_debug_get_stack_trace`, `dap_debug_get_scopes`, `dap_debug_get_variables` and `dap_debug_evaluate`. If
`dap_debug_launch` reports `running`, call `dap_debug_get_pending_events` or `dap_debug_get_output` before assuming the
program has stopped. End every session with `dap_debug_disconnect`. Only the Python adapter is configured.
