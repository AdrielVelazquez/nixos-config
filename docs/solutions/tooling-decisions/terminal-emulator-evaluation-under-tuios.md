---
title: Host-terminal choice under tuios, and why Kitty stays the default
date: 2026-10-20
category: tooling-decisions
module: modules/home-manager/ghostty.nix
problem_type: tooling_decision
component: tooling
severity: low
applies_when:
  - "Reconsidering Kitty as the host terminal for tuios"
  - "Judging a terminal on scrollback search or on how well it handles a multiplexer"
  - "Adding or testing a terminal module without changing the default"
retire_when: "Ghostty ships a release after 1.3.1 with remote control or scrollback piping, Rio gains scrollback piping, or tuios stops needing kitty graphics and kitty keyboard from its host; re-read the Ghostty release notes and rerun the checks in the Examples section"
tags: [terminal, kitty, ghostty, rio, tuios, multiplexer, home-manager, scrollback]
---

# Host-terminal choice under tuios, and why Kitty stays the default

## Context
A survey on 2026-10-20 compared Kitty 0.49.2 with Ghostty 1.3.1, Rio 0.5.28, Foot 1.28, WezTerm (nightly only), Alacritty 0.17, Contour 0.7, Monstar 1.0.1 and Attyx 0.4.16. The criteria were scrollback search, easy images, speed, multiplexer friendliness and Nix support. No candidate beat Kitty on all five. The reasoning below is what the Nix modules cannot show.

## Guidance
- **Judge terminals on what tuios needs, not on scrollback search.** tuios runs on the alternate screen, so the host terminal's scrollback and search see only tuios's own screen (see the comment in `modules/home-manager/kitty.nix`). Search and scrollback export are already tuios's own: its copy mode has `/` search, and `ctrl+shift+s` sends `tuios capture-pane` output to Neovim. The host must instead handle kitty graphics with Unicode placeholders, the kitty keyboard protocol with Super, synchronized output (mode 2026), OSC 52 and OSC 66. tuios's README names Ghostty, Kitty and WezTerm as hosts.
- **No terminal removes the double parse of an external multiplexer.** The multiplexer parses the child's output and re-emits a diff, so the outer terminal draws once but every byte is parsed twice. The measured cost is about 1-2 ms of latency and up to half the throughput under output floods (beuke.org typometer, Mar 2024; Kitty's own throughput table). That is small beside tuios's own pipeline, about 8 ms p50 in its docs. Native multiplexers (WezTerm mux, Kitty layouts) do not help when tuios is the multiplexer. Rex and iTerm2 `tmux -CC` are macOS-only. Ghostty parses tmux control mode but no GUI uses it, and its GUI PRs were closed unmerged in Sept 2026.
- **Kitty has no search UI of its own.** `ctrl+shift+f` in `kitty.nix` is a user-built fzf overlay, so parity with it means pipe-to-external or a native search, not a feature copy. Native search without a pipe: Ghostty (no regex) and Rio. Search with `pipe-scrollback`: Foot. Search with a Lua callback: WezTerm.
- **What eliminated each candidate for this setup.**
  - Alacritty: no images, no OpenType features.
  - Contour: no Unicode placeholders.
  - Foot: sixel only, ligatures refused upstream.
  - WezTerm: no stable release since Feb 2024, slowest throughput in published tests, Wayland rewrite in progress.
  - Monstar: no OpenType features, no Nix packaging.
  - Attyx: a built-in multiplexer that overlaps tuios.
- **Keep Kitty as default and trial Ghostty and Rio.** Ghostty is a documented tuios host with strong Home Manager support. Rio has the broadest image protocol coverage. Neither has remote control, so `kitty @ launch --type=tab` in `modules/home-manager/niri/scripts.nix` would become a new window.

## Why This Matters
Re-running the survey costs a lot of research, and the headline criteria mislead. Scrollback search looks decisive but tuios already owns it, and the "renders twice" worry looks decisive but applies to every terminal. The real filters are graphics placeholders, keyboard protocol and font features.

## When to Apply
- Someone proposes switching terminals because of search, benchmarks or multiplexer overhead.
- A new terminal appears. Check the same five things first: placeholders, kitty keyboard, mode 2026, OpenType features and Nix packaging.

## Examples
The trial modules are `local.ghostty.enable` and `local.rio.enable`, both off by default. To try one, set it to `true` in the host's user file, for example `users/adriel-cachyos/default.nix`.

Checks that worked without touching the real config:
- Ghostty: build the generated `ghostty/config` and run `ghostty +validate-config --config-file=<path>`. It exited 0.
- Rio has no validator. Copy the generated `config.toml` and theme into a temp `RIO_CONFIG_HOME`, append `[developer]` with `log-level = "DEBUG"` and `enable-log-file = true`, then launch `rio -e sleep 8` under `timeout`. Config problems appear in the log file Rio writes inside that directory. A clean run searched for the configured "Maple Mono NF" and logged no warnings.
- Enabled variant without editing the host: `homeConfigurations.cachyos-framework13.extendModules { modules = [ { local.ghostty.enable = true; local.rio.enable = true; } ]; }`.
- In Rio's binding tables write `"with"` quoted. Bare `with` is a Nix keyword and fails with "unexpected 'with', expecting 'inherit'".
- Ghostty's HM `clearDefaultKeybinds` emits `keybind = clear` first, so list back only the chords the terminal should keep.

## Related
- `modules/home-manager/kitty.nix`, `modules/home-manager/tuios.nix`
- Ghostty 1.3.1 release notes and tmux control-mode issue ghostty-org/ghostty#1935
- Rio docs at rioterm.com/docs/config and /docs/key-bindings
