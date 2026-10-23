# Pi omp-style UI

`local.pi.ui.enable` installs the pinned `@nguyenquangthai/pi-omp-theme` visual owner and a neutral-default-foreground adapter. It replaces Zentui, the local workspace header/footer, `managed-opencode`, and `zentui.json`; AST and fetch-only capabilities remain independent.

## Configuration

```nix
local.pi.ui = {
  enable = true;
  theme = "omp-reference"; # or "omp-dark", "terminal", "terminal-tinted"
  terminalThemes.enable = true;
  neutralForeground.enable = true;
  settings = { }; # recursively merged over managed piOmpTheme defaults
};
```

`omp-reference` samples the supplied omp screenshot (cyan keywords, green functions, gold variables). `omp-dark` ports stock omp dark. Both are strict Pi truecolor themes. The optional JSON-only `pi-terminal-theme` supplies palette-following alternatives; `terminal-tinted` assumes custom terminal palette slots, so is not the default. Select a theme temporarily in Pi's `/settings`; change `local.pi.ui.theme` for a managed default.

The managed configuration disables automatic theme selection, OSC background synchronization, startup presentation, and read-only tool replacement. It selects an independent primary model/path/git/cost/context row, a boxed rounded prompt, and a secondary extension-status row. AST reports `ast-grep RO`; concise LSP and role labels must keep the **entire aggregate** within the terminal width. Upstream omits an oversized aggregate rather than wrapping individual statuses. Three short statuses are tested at 120 and 80 columns; 40-column rendering is exercised, not guaranteed to show every status.

### Rounded boxed frame exception

Upstream 1.0.26's `StyledEditor.frameKind()` gives `style = boxed` precedence over `frame = rounded`, rendering thick rules. The named one-line package patch makes explicit rounded frames work with boxed style. Documented presets do not avoid this conflict: rounded dock hosts its own primary status (duplicating the standalone row), and border placement hides the secondary statuses. Boxed remains the configured style so it does not host a duplicate status. Re-test and drop the patch when upstream honors this combination.

A second named patch translates `StyledEditor.handleMouse()` coordinates past the prompt, padding and rounded side border before delegating to native hit testing. Without it, clicking a text column selects the wrong cursor position. The existing real-PTY `abcXdef` click test covers this cutover regression; remove the patch once upstream handles its own rendered geometry.
## Immutable settings and compatibility

Normal loading, two `/reload` calls, `/new`, and model turns preserve managed settings symlinks. **Do not use `/pi-omp-theme persist global ...` or `persist project ...` for managed files**: upstream saves through atomic rename and replaces the `settings.json` symlink with a regular file. Session-only commands are temporary; persist desired values in Nix instead.

The visual owner's rich tool/message styling uses guarded private host adapters. The neutral adapter wraps exported `Markdown.render` and `CustomEditor.render` because Pi 1.3.0 has no public default-foreground hook. It preserves explicit foregrounds, reopens theme text after resets, reads the live theme, is idempotent across factory calls, restores owned methods on shutdown, and does nothing outside TUI mode. Both need review on Pi upgrades. Native highlight.js remains in use: no Shiki/TextMate engine, semantic LSP coloring, or runtime grammar downloads are added.

## Verification

```sh
rtk nix eval .#homeConfigurations.cachyos-framework13.activationPackage.drvPath
rtk nix build --no-link .#checks.x86_64-linux.pi-ui
```

The sandbox check validates both palettes through Pi's strict loader; tests adapter lifecycle/ANSI behavior; drives real Pi with generated settings and a local scripted provider through read/edit/native question/Tuios flows, Unicode/CJK/emoji paste/mouse/resize/reload/new; and checks print/JSON/RPC runs for empty stderr. No real model is called. The checked screenshot is `docs/assets/pi-omp-parity/ui.png`.

The screenshot was captured with `/tmp/pi-lab/lab.py` from the check's generated agent directory (managed settings/web-policy symlinks copied into a writable throwaway parent), using three local scripted provider requests. LSP/role status values in this UI-only screenshot are fixture labels, not proof that those separate integrations ran; AST is the actual managed extension.
