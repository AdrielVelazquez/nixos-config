# Pi debug adapters (DAP)

`local.pi.dap.enable` (on by default with `local.pi.enable`) installs the pinned `@ian-pascoe/pi-dap@0.10.1`
extension through Nix, with five debug adapters from nixpkgs referenced by store path. The package has no adapter
discovery or installer, and nothing here runs `pi install`, a lifecycle script or a runtime download.

It gives the **interactive session** twelve tools: `dap_launch`, `dap_set_breakpoints`, `dap_continue`, `dap_next`,
`dap_step_in`, `dap_step_out`, `dap_pause`, `dap_stack`, `dap_variables`, `dap_evaluate`, `dap_status` and `dap_stop`.
Launching, stepping and evaluating run the debuggee's code, so native children never get them: the entry is not a
required child extension and no role's `tools:` list names a `dap_*` tool (`pi-dap` asserts both).

## Profiles

`dap_launch` takes a `profile`; each names an adapter:

| Profile | Adapter | For | Notes (all observed in `checks.pi-dap`) |
|---|---|---|---|
| `go` | `dlv dap` (delve, TCP) | Go | Builds `program` itself (`mode: debug`) with the Nix Go toolchain on its PATH. Delve routes the program's stdout to its own process, so the model does not see program output. |
| `python` | `python -m debugpy.adapter` | Python | debugpy from nixpkgs, which also runs the debuggee. Program output reaches the model. |
| `node` | `vscode-js-debug` (TCP) | Node | The package's one supported adapter. The debuggee's `node` is the one on your PATH. Program output reaches the model. |
| `native` | `gdb --interpreter=dap` | Rust, Zig, C, C++ | Debugs a **prebuilt** binary with debug info (`rustc -g`, `cargo build`). gdb treats `dap_evaluate` text as a gdb command, so write `print a + b`; that also means it can run any gdb command, `shell` included. |
| `dart` | `dart debug_adapter` | Dart | Uses the SDK your Neovim packages already install. `dap_launch` can answer `running` before the breakpoint stop is observed; `dap_stack`/`dap_status` then show it. |

Only Node is a supported workflow upstream; the other adapters are "experimental: may work, no compatibility
promise". Each was exercised end to end here (below), but a newer adapter or package version can change that.

## Trust

A debug adapter is an executable. Pi reads the `dap` key from the global `settings.json` (Nix-generated) and, **only
for a trusted project**, from its `.pi/settings.json`, which may add adapters. `checks.pi-dap` shows both halves with
the same hostile project: untrusted, the adapter is never started; trusted (`--approve`), it is. Do not trust an
unfamiliar repository to look at it.

## Settings

```nix
local.pi.dap = {
  timeouts.startupMs = 30000;      # defaults: startup/request 30 s, execution 30 s, shutdown 5 s
  adapters.gdb.enable = false;     # drop one adapter; profiles must then be disabled too
  profiles.native.enable = false;
  profiles.rustlldb = {            # an extra profile on an existing adapter
    adapter = "gdb";
    arguments = { };
  };
};
```

Startup and request timeouts are raised from the package's 10 s: the first start of the Dart and js-debug adapters
is slow. Adapter `command`s are absolute store paths; `runtimeInputs` (Go for delve) are prepended to the adapter's
PATH. Persist choices here, not by editing `~/.pi/agent/settings.json`: every switch resets it.

## Limits (the package's V1 boundary)

Linux, stdio or TCP adapters, one active debug session, source breakpoints and core execution control. No attach,
restart, function/data breakpoints, logpoints, memory or disassembly views. Child sessions are folded into one
session only for `vscode-js-debug`.

## Closure

Measured against the generation installed when this was written, the new store paths total about 107 MiB:
gdb, debugpy with its Python environment, `vscode-js-debug`, `source-highlight` and `libipt`. Delve and the Dart SDK
were already installed by the Neovim configuration. (Choosing `lldb-dap` for native code instead of gdb would add
about 1.6 GiB of LLVM; gdb's DAP mode was chosen because it passed the same session with the smaller closure.)

## Verify

```sh
rtk nix build --no-link .#checks.x86_64-linux.pi-dap
```

For each language the check runs real Pi with a scripted model and the real adapter on a small program: set a
breakpoint, launch, stop inside `add()`, read the stack, evaluate `a + b` to 5, continue to exit. It also runs the
untrusted-project and trusted-project cases above. It is a scripted session, not a test of how a model uses the tools.
