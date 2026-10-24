# Pi persistent Python `eval` and codemode

Two options, both on with `local.pi.enable`:

- `local.pi.eval.enable` registers an `eval` tool: one Python cell per call, run by a kernel whose variables, functions and
  imports survive from call to call. The tool is first-party (`dotfiles/pi/extensions/eval.ts`, `eval-kernel.ts`,
  `eval-core.ts`, `dotfiles/pi/eval/runner.py`); the interpreter is `local.pi.eval.python.package` (nixpkgs `python3`).
- `local.pi.codemode.enable` adds `+codemode` to `defaultTools`, so Pi's native `codemode` tool (sandboxed JavaScript that calls
  other tools) is in the interactive session. Children already had it through their role files.

## What the model gets

`eval` takes `{ code, timeout?, reset? }`.

- **State.** The namespace lives as long as the session in this Pi process; compaction does not clear it. A new, resumed or
  forked session, and `/reload`, end the kernel (Pi's `session_start` and `session_shutdown`). When the first call after that finds
  earlier `eval` results in the session, the result says the old variables are gone. `reset: true` discards the kernel, and says so.
- **Python.** `python -I -u`, so `PYTHON*` variables and user site-packages are ignored and libraries come only from
  `local.pi.eval.python.package`. Cells run with plain `exec`: a final expression is printed, a traceback shows the cell's own
  frames with their source lines, `exit()` ends the cell and not the kernel. There is no IPython (`!cmd`, `%magics`) and no
  top-level `await`. stdin is `/dev/null`.
- **Output.** stdout and stderr are merged in the order written, and so is the output of child processes the cell starts. It keeps
  the last 2000 lines or 50 KB; a longer output is written in full to a temp file whose path the result names. A cell that prints
  more than 64 MiB is interrupted. Output printed by a background thread between cells is discarded.
- **Failure.** A traceback, a timeout, a cancel, a killed kernel and an output overflow are all failed tool results. A traceback
  or a timeout leaves the namespace intact. `timeout` (default 120 s, at most 3600 s) sends Ctrl+C to the kernel's process group, so
  a child process the cell started is interrupted too; a kernel that ignores it is killed after 5 s and the result says its
  variables are gone (the next call starts a fresh kernel without repeating the news).
- **Helpers in the namespace.**

  | Name | Does |
  |---|---|
  | `tool.<name>(**args)`, `tool["name"](...)` | calls any callable tool; raises `ToolError` when it fails |
  | `read(path, offset?, limit?)` | raw file text, no line anchors |
  | `write(path, content)` | the session's `write` tool, so formatting and diagnostics run |
  | `env(key?, value?)` | the environment, one variable, or set one for the kernel and its children |
  | `image(path \| bytes \| tool image block)` | attaches an image to the result |
  | `state()` | lists variables with their types and the imported modules, to rediscover state after a compaction |

  The design sketch called the last helper `vars()`; that would shadow the builtin, so it is `state()`.

## Tool re-entry

`tool.<name>()` goes through `ctx.executeTool`, the path codemode uses: argument validation, the `tool_call` and `tool_result`
handlers and the `tool_execution_*` events run as for a model-issued call, with ids `<eval call id>/<n>`. The nested call is not
a separate transcript entry. So `write()` of a Go file returns the formatter's note and the LSP diagnostics, `tool.read` returns
hashline's anchored text while `read()` returns the raw text, and `tool.bash` works. `tool.eval` is refused.

A call's value is the tool's structured value when it declares one, its text when the result is only text, and otherwise the list
of parts (images stay `{ type: "image", data, mimeType }`, which `image()` accepts). The cell's timeout includes the time nested
calls take. Calls run one at a time (`executionMode: sequential`), and the tool declares `reachesTools` from the source (`tool.x`,
`tool["x"]`, `write()`; a bare `tool` reaches all) so MCP servers still connecting finish first.

## Scope and authority

The kernel runs arbitrary code with the user's authority and Pi's whole environment, including any credential Pi holds there, the
same as the `bash` tool; `tool.<name>()` reaches every callable tool of the session, `write`, `edit` and `bash` included. There is
no sandbox and no permission prompt.

- Interactive session only. The entry is not a required child extension and no role file names `eval`, so `build`, `plan`, `scout`,
  `explore` and `title` children never have it.
- `/plan` does not restrict tools in this configuration (`modelRoles.planMode.readOnly` is `false`). With it set, the plan toolset
  is a whitelist that names neither `eval` nor `codemode`.
- Nothing is installed at run time: no pip, no venv, no download. A project's own virtualenv packages are not visible to `-I`.
  `local.pi.eval.python.package = pkgs.python3.withPackages (p: [ p.requests ])` adds libraries from Nix.

## Process model

The kernel is a child in its own process group. The control channels are two private pipes (descriptors 3 and 4, moved to
non-inheritable descriptors at start and closed in their original slots), so neither a cell's children nor the cell can reach
them. Every cell ends with a marker on stdout; the host waits for the marker and the `done` message before it returns, so no
output byte is lost or reordered. An idle kernel exits when the pipe closes, and `PR_SET_PDEATHSIG` kills a busy one when Pi
dies; a child process a cell started can outlive Pi.

## Verification

`checks.x86_64-linux.pi-eval` runs 14 kernel unit tests against the real interpreter (persistence, tracebacks, stderr and child
ordering, control-channel isolation, marker-shaped and 3 MB output, timeout and kill, cancel with a child process, overflow, tool
calls, helpers, host death) and then real Pi with a loopback provider:

- **kernel**: variables survive separate model turns, a traceback and a timeout; `reset` discards them; output order across stdout,
  stderr and a child; a kernel killed from inside reports it once and restarts; truncation to a file; an image reaches the
  model; `tool.eval` is refused; codemode is declared (its description is 1404 characters, recorded in
  `codemode-description-chars.txt`).
- **tools**: with format-on-write, the LSP and hashline, `write()` of an unformatted Go file returns the formatter's note and the
  `declared and not used` diagnostic in that order, `tool.read` is anchored while `read()` is raw, `tool.bash` works.
- **resume**: a second Pi process resumes the session of the first; its kernel is fresh and the first result says the variables of
  the earlier eval calls are gone, and nothing more once it has said so.
- The Nix assertions: the entry is a plain extension and not a required child extension, no role file mentions `eval`, and the
  `/plan` toolset names neither `eval` nor `codemode`.

The plain-Pi card (`eval python` plus the code) and the omp-theme card render in a real fullscreen terminal; neither is covered by
a permanent check.

## Not built

- A persistent JavaScript kernel: `codemode` is the JavaScript path and stays sandboxed (no file system, network or timers) with a
  JSON `store` of at most 1 MiB.
- IPython magics, `%pip`, top-level `await`, notebooks.
- omp's `agent`, `workpool`, `judge` and `completion` bridges, background cells and auto-backgrounding.
- State across Pi restarts. A resumed session is told that its variables are gone.
