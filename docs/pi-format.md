# Pi format-on-write

`local.pi.format.enable` (on by default with `local.pi.enable`) formats the file the model just wrote, the way
conform.nvim does on save in your Neovim. It is a first-party extension, `dotfiles/pi/extensions/format-on-write.ts`
(helpers in `format-core.ts`), with no npm package, install script or network access. Formatters are nixpkgs binaries
referenced by store path.

## What happens

After a **successful** native `edit` or `write`, Pi's `tool_result` event reaches this extension first. If the file's
extension has a formatter, the file is piped through it on stdin and, when the output differs, rewritten in place.
The model's tool result then gains one note:

```text
Formatted with gofumpt: +2/-1 lines. The file on disk now includes the formatter's changes below; base any later edit on this content. Anchors (LINE#HASH) from before this note are stale: re-read the file before an edit that uses them.
@@ -3,2 +3,3 @@
 ...
```

The note matters: Pi's native `edit` matches `oldText` exactly and the hashline `edit` (`docs/pi-hashline.md`) matches
line anchors, so a model that does not know the file was reformatted would fail its next edit either way. The diff is
bounded (`maxDiffLines`, default 40); a larger one ends with `… N more diff lines`, and one too large to compare keeps
only counts.

The extension loads before the LSP extension (`lib.mkOrder 900`; Pi runs `tool_result` handlers in load order), so the
post-edit diagnostics in `docs/pi-lsp.md` describe the formatted file. It is also a required child extension, so native
`build` and `plan` subagents format their writes too.

## Formatters

| Name | Package | Files | Notes |
|---|---|---|---|
| `gofumpt` | gofumpt | `.go` | Same formatting as gopls with `gofumpt = true`. |
| `jq` | jq | `.json` | As in Neovim. JSONC with comments fails and is skipped. |
| `nixfmt` | nixfmt | `.nix` | |
| `ruff` | ruff | `.py`, `.pyi` | `ruff format`; reads the project's `pyproject.toml`/`ruff.toml`. |
| `stylua` | stylua | `.lua` | |
| `shfmt` | shfmt | `.sh`, `.bash` | **Only below an `.editorconfig`**: with no config it indents with tabs. |
| `rustfmt` | rustfmt | `.rs` | `--edition` comes from the nearest `Cargo.toml` (workspace inheritance followed; 2021 without a manifest). |
| `zig` | zig | `.zig`, `.zon` | `zig fmt --stdin`. |
| `opentofu` | opentofu | `.tf`, `.tfvars` | `tofu fmt -`. OpenTofu rather than Terraform, which nixpkgs marks unfree (BUSL); the output is the same. |
| `biome` | biome | `.ts` `.tsx` `.mts` `.cts` `.js` `.jsx` `.mjs` `.cjs` | **Only below a `biome.json`/`biome.jsonc`**: its defaults (tabs, double quotes) would rewrite Prettier projects. |

The first five are your Neovim conform set. A marker only counts when it lies inside the session's working directory.

**Closure cost.** Measured against the generation installed when this was written, the entry adds about 3.7 GiB, nearly
all of it `zig` (1.8 GiB) and `rustfmt` (1.7 GiB), which carry LLVM/clang libraries; OpenTofu adds 148 MiB and Biome
134 MiB. To skip the two large ones:

```nix
local.pi.format.formatters.zig.enable = false;
local.pi.format.formatters.rustfmt.enable = false;
```

Override or extend in Nix:

```nix
local.pi.format = {
  timeoutMs = 5000;                       # a slower formatter is killed, the file stays as written
  formatters.gofumpt.enable = false;
  formatters.prettier = {                 # args may use {file} and {cargoEdition}
    package = pkgs.nodePackages.prettier;
    command = "prettier";
    args = [ "--stdin-filepath={file}" ];
    extensions = [ ".css" ];
  };
};
```

## Files a bash command wrote

A heredoc (`cat > main.go <<'E'`), `printf >`, `sed -i` or a generator writes files the edit tools never see. With
`local.pi.format.afterBash` (default on) the extension stamps the working tree through `git status` before and after
every `bash` command (one status each side, 800 ms deadline each, skipped outside a repository and in a tree with more
than 4000 dirty paths) and compares mtime and size of every dirty file. The result then ends with one sentence naming
what the command changed, capped at eight files and leaving out `node_modules`, `vendor`, `.git` and deleted files:

```text
This command changed 2 files: main.go, notes.md.
```

A **successful** command's changed files are then formatted exactly like an `edit`'s, each with its own `Formatted
<file> with <formatter>` note. A failed command is only reported, never formatted, and a command that changed nothing
adds nothing. A file that was already dirty and that the command did not touch is not the command's: never listed, never
reformatted. A command that reverts a file (`git checkout -- f`) leaves the dirty set and so is not reported.

Limits: two commands running at once share each other's changes; a file rewritten with identical size inside the clock's
resolution is missed; LSP diagnostics still cover only `edit` and `write` (pi-lsp offers no way to ask for them from a
`tool_result` handler), so a bash-written file is formatted but not diagnosed until the model asks with `lsp_diagnostics`.

## What it will not do

A file is left exactly as written, with no note, when: the tool result is an error; the path is outside the working
directory, a symlink, not a regular file, larger than `maxFileBytes` (1 MiB) or not valid UTF-8; the formatter exits
non-zero (typically a syntax error mid-edit; LSP diagnostics report those), times out, prints more than four times
`maxFileBytes`, or exits cleanly with empty output for a non-empty file. A formatter whose executable is missing is
reported once and skipped for the session.

Not covered: files changed through any other tool (including `ast_grep` rewrites if you add them later),
formatting by LSP `textDocument/formatting`, range formatting, and project-level formatter selection beyond what each
tool does itself (ruff, stylua, shfmt, biome and rustfmt read their own config; gofumpt, jq, nixfmt, zig and tofu
have none).

Two writers on the same file are serialized through Pi's own file-mutation queue; an external editor writing at the
same moment is not.

## Verify

```sh
rtk nix build --no-link .#checks.x86_64-linux.pi-format
```

The check runs the unit tests, asserts that the format entry precedes the LSP entry in the generated extension list
and is a required child extension, then loads the **generated entry** and formats one real sample per formatter with
the nixpkgs binaries, plus idempotence, the marker gates and a syntax-error file.
