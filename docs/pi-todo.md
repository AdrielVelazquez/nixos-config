# Pi task tracking

`local.pi.todo` extends the existing first-party `todo` tool. It is enabled with Pi on Framework and Razer, without extra npm packages, runtime installers, or writable configuration files. These changes do not enable the tool in delegated children or change any provider, routing, or permission policy.

## Workflow and richer tasks

The original operations remain:

- `init` replaces the list and starts its first task; `add` appends tasks.
- `start` moves the single active marker and can reopen completed work.
- `done`, `block`, and `remove` automatically advance when necessary.
- `block` requires a reason for an external blocker; `unblock` makes it pending again.
- `view` reads the list. `get` reads one task with its description and metadata. `clear` resets the list and IDs.

`items` accepts strings or task objects, including mixed batches:

```javascript
todo({op: "init", items: [
  "Inspect the API",
  {text: "Implement the fix", description: "Preserve the existing response shape", owner: "build", blockedBy: [1]},
  "Verify the result"
]})
todo({op: "update", id: 2, text: "Implement and test the fix", activeForm: "writing regression tests"})
todo({op: "update", id: 2, metadata: {priority: "high", obsolete: null}})
todo({op: "get", id: 2})
```

`update` can edit `text`, `description`, `activeForm`, `owner`, `metadata`, and dependencies, without changing workflow status. Use the original workflow operations to change status. Null clears optional text fields or all metadata; metadata objects merge keys, with null deleting an individual key.

Task IDs remain stable until `init` or `clear`; removing a task does not reuse its ID. At most 100 tasks are retained. Text, activity labels and owners are limited to 300 characters, descriptions to 4000, new blocked reasons and search queries to 1000, and metadata to 8192 UTF-8 JSON bytes with at most 12 nesting levels. Metadata must be finite, acyclic JSON data. Invalid calls fail and leave the state unchanged.

## Dependencies and blockers

`blockedBy` lists prerequisite task IDs. `update` also accepts `addBlockedBy` and `removeBlockedBy`. References and cycles are checked before the entire change is committed; batches are atomic. Remove references before removing a prerequisite task.

Dependencies are **annotations, not scheduling gates**: neither explicit `start` nor automatic advancement waits for them. The agent uses them to sequence work. The separate `blocked` status and reason remain available for credentials, decisions, unavailable services, and other blockers that are not another task.

## Reading and filtering

```javascript
todo({op: "view", status: "blocked"})
todo({op: "view", owner: "build", query: "regression"})
```

Filters accept `pending`, `in_progress`, `done`, or `blocked`; owners match exactly, and text queries are case-insensitive across task text, description, activity, owner and blocked reason. Filtered reads return the canonical full state in tool details, so a filtered view cannot erase hidden tasks. Progress always refers to the whole list.

`/todos [status] [owner=name] [query words]` prints the list through Pi's native notification API, including in RPC clients. For example, `/todos blocked owner=build credentials`. Use the tool for owner names containing spaces.

## Widget and localization

The TUI checklist stays above the editor. Its compact view keeps the active task visible even when it is near the end of a long list. Activity labels, owners and dependency IDs appear inline. Empty and entirely finished lists leave no widget. RPC clients receive a composable status instead of a terminal-only component.

- Ctrl+Shift+T collapses or expands the widget by default. The collapsed view retains progress and a key hint.
- Pi's native Ctrl+O tool expansion shows every task, overriding local collapse until tool output is collapsed again.
- Optional completion hiding removes completed rows on the following agent run, not the stored state. Reopening a task makes it visible again.
- Terminal widths, wide characters, theme changes and task-supplied control characters are handled by the native rendering helpers and sanitized presentation.

```nix
local.pi.todo = {
  maxWidgetLines = 8; # 3..101 content rows, heading included; one trailing spacer is additional
  collapseKey = "ctrl+shift+t"; # null disables the binding; use Pi's normal key syntax
  locale = "en";
  hideCompleted = false;
};
```

UI locales: `en`, `de`, `es`, `fr`, `pt`, `pt-BR`, `ru`, `uk`, `zh`. Only presentation labels are localized: task text, schema, model-facing results and validation errors stay in their original language/English. Direct extension use falls back to English for unsupported locales; Nix validates its locale enum.

The options are passed through the Nix-generated extension entry. Do not edit `~/.config` or run a separate configuration installer. A future activation is a separate, explicitly approved action.

## Persistence and session boundaries

Every state-changing call appends a versioned `pi-todo-state` entry to the session branch as well as returning full tool-result details. This matters for calls from `codemode` or Python `eval`: Pi records nested calls in the outer tool, without a standalone todo result to replay. A `view`/`get`, a failed call, or a no-effect update does not append a new snapshot.

Loading, tree navigation and compaction reconstruct only the active branch. Existing sessions using standalone todo result details remain readable; no migration or external database is needed. Malformed snapshots are skipped and replayed data is cloned rather than aliased.

Runtime task and widget state is keyed by session ID. A child or sibling cannot mutate the foreground list or repaint its widget. Shutdown removes only that session's slot and retires its render context before clearing the UI. The Nix role policy still deliberately omits `todo` from children; session isolation is defense against accidental in-process reuse, not permission to expand their tools.

## Verification

`checks.x86_64-linux.pi-tools` includes the original and feature unit tests, session/lifecycle tests using real Pi and a scripted loopback model, nested `codemode` and Python restart checks, and a real fullscreen PTY using the managed OpenCode skin and a French widget. It covers collapse, native expansion, resize and active-tail visibility. `pi-ui` and `pi-ui-opencode` retain the existing skin contracts.

The tests use throwaway HOME/config directories and synthetic credentials. They do not activate the system or test live-model planning quality. Framework's exact Home Manager eval and Razer's embedded Home Manager eval pass; Razer's full system eval is currently blocked by pre-existing obsolete initrd options, reproduced at the feature branch's unchanged base commit.
