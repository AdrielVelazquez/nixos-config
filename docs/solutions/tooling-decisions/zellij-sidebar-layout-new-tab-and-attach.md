---
title: Zellij sidebar layouts need an explicit new-tab template and `zellij attach`
date: 2026-10-19
category: tooling-decisions
module: modules/home-manager/zellij.nix
problem_type: tooling_decision
component: tooling
severity: medium
applies_when:
  - "Putting a plugin pane such as a vertical tab bar in a Zellij layout"
  - "Making plain `zellij` reattach to one named session"
  - "Testing Zellij plugins or keybindings without a real terminal"
retire_when: "A Zellij release after 0.45.1 builds new tabs from default_tab_template with a terminal pane and honors default_layout together with attach_to_session; check the changelog and rerun the pty check in the Examples section"
tags: [zellij, layout, plugin, home-manager, new-tab, session]
---

# Zellij sidebar layouts need an explicit new-tab template and `zellij attach`

## Context
`local.zellij` shows tabs in a right-hand `zellij-vertical-tabs` pane. The layout and session settings that look right on paper fail in three ways on Zellij 0.45.1, and none of them print an error to the user.

## Guidance
- Write the first `tab { ... }` and a `new_tab_template { ... }` with the same literal body. Do not use `default_tab_template` with `children`. A bare `tab` creates no terminal pane, and the new-tab blueprint Zellij derives from `default_tab_template` has `children` but no sidebar. Ctrl+t then n logs `spawn_terminals_for_layout: 0 tiled + 0 floating panes created`, discards the tab, and leaves one tab.
- Do not set `session_name` or `attach_to_session` in `config.kdl`. With `attach_to_session true`, Zellij ignores `default_layout` and starts the stock tab-bar layout. `session_name` alone makes a second bare `zellij` fail with "session already exists". Use `zellij attach --create main` instead, which keeps the configured layout (`zj` alias in the module).
- `default_mode "locked"` selects Zellij's unlock-first keys. After Ctrl+g plain letters (`p`, `t`, `n`, ...) are mode switches and typing never reaches the pane, so lock again with Ctrl+g before typing. Keybinds under `shared { ... }` work in both states.

## Why This Matters
The failures look like plugin or terminal bugs. The tab that never opens leaves no error. The ignored layout shows a working Zellij with the wrong bars, and the lost keystrokes look like a stuck terminal.

## When to Apply
- Any layout with fixed-size plugin panes around the terminal pane.
- Any change to how a Zellij session is created or reattached.

## Examples
Check a layout by starting a real client in a pty, not `attach --create-background`. A background session has no client, so a third-party plugin pane stays blank and `new-tab` can report an id for a tab that does not exist.

1. Start `zellij --config-dir <dir> attach --create main` in a pty of a fixed size, for example 100 by 18.
2. Feed the output to `pyte` and read the screen. `nix build nixpkgs#python3Packages.pyte` and `...wcwidth` provide both.
3. Send the keys as bytes, for example `\x07` for Ctrl+g and `\x1b[116;6u` for Ctrl+Shift+t.
4. Pre-seed `$XDG_CACHE_HOME/zellij/permissions.kdl` with the plugin path so no permission prompt covers the pane.
5. Send `echo` and similar text only in locked mode.

## Related
- `modules/home-manager/zellij.nix`
- TODO.md entries for the pinned `zellij-vertical-tabs` release and `gentle-agent-state`
