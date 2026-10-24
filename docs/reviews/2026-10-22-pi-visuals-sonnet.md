# Review: full visual profile delta (feat/pi-audited-capabilities, 9b792cc → 3b91b22)

Reviewer: Claude Sonnet 5.5 subagent. Read-only: no repo/index/HEAD/config edits, no real credentials,
inference, browser or daemon use. Scratch probes live only in `/tmp/opencode/visuals-probe/`
(`probe.ts`, `probe2.ts`, `c1.ts` and their `.out` files; `visuals.ts` there is a byte-identical copy of the repo file).

## Snapshot reviewed

- The delta was committed as `3b91b22` (23:05:34) while I was reviewing. Every file I read was last modified
  22:43–22:56, so the commit matches what I read. Line numbers below refer to that content.
- The live Home Manager generation is already the new one (gen 321 `hz4ajz86…`, activated 22:59).
  `~/.pi/agent/settings.json` and `zentui.json` are symlinks into the new store, with `theme=managed-opencode`
  and `quietStartup=header`. I treated this as the user's authorised activation and did not check it further.
- Verification logs, observed only (I did not rebuild):
  - `/tmp/opencode/pi-full-visuals-verification.log` (22:55) is a FAILED run with an empty `.json`. The
    failure is `capability-ui.py` line 135, the `answer == ['Yes fixture', None]` assertion. It ran the old
    script, before the test-race fix now at `capability-ui.py:135-137`. It is stale, not a current failure.
  - `…-activate-verification.json` (22:58): `pi-capabilities-actual-ui` built (passed) plus the HM generation.
  - `…-final-verification.json` (23:01:49) has 14 entries. Its log shows the format check, base-workflow,
    tuios, routing, headroom, capabilities-runtime and loopback checks being built, with no failure.
  - So the final state looks green, but I did not witness a single log that shows all 14 passing.

Evidence labels: **[E]** executed or observed by me (synthetic probe or actual artifact), **[C]** read from
code or SDK source, **[H]** hypothesis, not demonstrated.

## Readiness

- **Critical: none.**
- **Important: 1.** Header and footer show a stale thinking level, which contradicts the Zentui editor line.
  It is a display-truthfulness defect with a one-line fix. It does not touch tool execution, config or
  safety. It is not an activation blocker. I would fix it before merge.
- Minor: 9 items.
- The core safety claims hold on this evidence:
  - Single header/footer owner.
  - Tool registration rejected.
  - Source identity unchanged.
  - No polling or quota probes.
  - Config files stay immutable.
  - Lifecycle across reload and quit.
  - Control-sequence handling is good except for C1 characters.
  - Widths down to 2 columns.

## Critical

None found.

## Important

### I-1. Header and footer thinking level goes stale; `thinking_level_select` is not subscribed
- `dotfiles/pi/extensions/visuals.ts:37` stores `state.thinking` only inside `refresh()`. The footer
  (`:60-66`) and header (`:81`) render that cached value.
- The subscribed events are `agent_start`, `ui_prompt_*`, `agent_settled`, `model_select`, `session_info_changed`,
  `session_compact`, `session_tree` and `tool_result` (`:86-99`). `thinking_level_select` is missing.
- **[C]** Pi 1.3.0 emits `thinking_level_select` from `setThinkingLevel` whenever the level actually changes
  (`agent-session.js:2087-2102`). That covers Shift+Tab cycling and `pi.setThinkingLevel`.
- **[C]** `setModel` applies the per-model or default thinking level before it emits `model_select`
  (`agent-session.js:1984-1995`). So `model_select` refreshes are correct for plain model switches.
- **[C]** The managed routing command does it in the wrong order for us (`routing.ts:23-25`):
  `await pi.setModel(model); pi.setThinkingLevel(route.thinking)`. After `/plan` or `/build`, the header
  and footer show the pre-route thinking level. No visuals refresh follows until `agent_start` or `tool_result`.
- **[C]** The Zentui editor line (`metadataFormat "$model $provider( $thinking)"`) does subscribe to
  `thinking_level_select` (zentui `index.ts:1997`). The editor line and the header/footer can therefore
  disagree while idle.
- **[E]** Synthetic probe, `probe.out:16-26`. The stub fires `session_start`, then thinking changes
  high→low without an event. The footer keeps `BUILD · high` until a `model_select` is emitted, which then
  shows `low`. This reproduces the subscription gap, not a real Pi run.
- **Real effect:** a user who cycles thinking or runs `/plan` or `/build` sees the previous thinking level in
  both panels. The state is "truthful" again only after the next turn.
- **Fix:** add `pi.on("thinking_level_select", (_e, ctx) => { refresh(ctx); });`.
- **Test:** make the fixture model `reasoning: true` and add a `/think` fixture command that calls
  `pi.setThinkingLevel("low")`. Then assert the footer and header text.

## Minor

### M-1. Footer height is unbounded, and statuses are unsorted and unstyled (`visuals.ts:67-71`)
- Statuses are joined with `·` and wrapped with `wrapTextWithAnsi`, with no line cap.
- **[E]** `probe2.out`: three statuses totalling about 500 chars give 8 footer lines at width 120, 20 at
  width 40, 36 at width 20 and 71 at width 10. Native truncates to one line.
- Insertion order is used (`ZZZ · AAA`). Native sorts by key (`footer.js:256`) and truncates to one line
  (`:260`). Status colours are stripped by `plain`.
- Today's statuses are short: `managed-routing`, `ast-grep`, and a few others. The risk is latent. A long
  status from a future extension would eat the transcript area, because the footer is fixed-region.
- **Fix:** sort by key, truncate each status or the joined line, and cap total lines (for example 2).

### M-2. `plain()` does not strip C1 controls (`visuals.ts:5`)
- **[E]** `c1.out`: `\u009b31m` (C1 CSI) and `\u009d…\u009c` (C1 OSC/ST) survive. ESC CSI, ESC OSC (BEL and
  ST), APC, CR and tab are removed. Lone ESC becomes a space. DCS payload text survives as visible text,
  which is harmless.
- Zentui's own user-message sanitiser handles `\x7f-\x9f` (`user-message-osc.ts` `terminalControlPattern`).
  The new code is weaker than the bundled one.
- Inputs that reach it: `ctx.cwd` (directory name), model id/provider, and other extensions' status text.
  xterm-class terminals honour UTF-8-encoded C1 controls.
- Severity is low: the sources are mostly local or trusted, and the bidi overrides `U+202A-E` and
  `U+2066-9` also pass.
- **Fix:** extend the character class to `\x80-\x9f` and strip bidi overrides.

### M-3. "0" conflates zero with unreported usage (`visuals.ts:29-33,61-62`; `docs/pi.md:55`)
- Docs say "Unknown usage is shown as unknown". That is true for CONTEXT only. `getContextUsage()` returns
  null after compaction, and the footer shows `—`.
- **[E]** `conversation.txt:42-43` and the screenshot show `IN 0 OUT 0` and `CACHE —` after two real requests.
  The synthetic provider omitted usage, so a provider that reports nothing looks like zero.
- With input tokens present but no cache fields, `CACHE 0%` (`:61-62`) says "no cache hits", not "unknown".
- The cache percentage is cumulative: `cacheRead / (input + cacheRead + cacheWrite)` over all entries.
  **[E]** Arithmetic verified in `probe.out:36-39`: 60% for the sample data.
- The PTY never exercises non-zero usage.
- **Fix:** track whether any assistant message reported `usage.totalTokens > 0` or `cacheRead`/`cacheWrite`
  ever being defined. Show `—` otherwise. Alternatively soften the docs sentence.

### M-4. Proxy label is a static environment-derived policy (`visuals.ts:45`)
- `HEADROOM REQUIRED` is shown for every model once the launcher exports `LLM_PLATFORM_INFERENCE_PROXY_REQUIRED=1`.
  That variable is set because an llm-platform adapter exists (`pi-work.nix:76`, `headroom-pi.py:295`).
- **[C]** It does not follow the active provider. Attribution is provider-scoped by origin header
  (`headroom.ts:64-72`).
- It does not show failure. `headroom.ts:38,59-63` flips `valid=false` and the `input` handler blocks, but
  the label stays `HEADROOM REQUIRED`.
- `docs/pi.md:55` already says "required routing contract, not a health probe". So it is documented.
  The wording can still read as an assurance, and `NO PROXY CONTRACT` reads oddly.
- **Fix:** consider `HEADROOM POLICY`, or key it off `ctx.model.provider`. A health indicator would need a
  new state signal, which is out of scope.

### M-5. Layout cosmetics (all [E], from the actual PTY artifacts)
- A double horizontal rule sits between the Zentui editor's bottom border and the footer's top rule
  (`narrow.txt:37-38`, `conversation.txt:40-41`). One row is wasted.
- The footer top line wraps at width 40 so a continuation line starts with the separator
  (`narrow.txt:39-40`: `│  READY`).
- The routing status string is repeated: `BUILD` in the top line and `build` in the status line
  (`conversation.txt:42,44`). Excluding `managed-routing` from the status join would remove the duplicate
  while keeping `/plan` detail. Alternatively keep it, since in production it carries `plan: provider/model (thinking)`.
- **[C]** The native footer (`components/footer.js:134-185`) colours context `warning` above 70% and `error`
  above 90%. It also shows the window size (`4.3%/100k`) and an `(auto)` compaction marker, and it prints
  `?` for unknown context. Visuals shows a bare `CONTEXT 4.3%` with no threshold colour and no window
  size. That is the one native signal I would restore, since it warns before compaction.
  `getContextUsage()` carries `contextWindow`. A two-line change to colour by `state.context` and append
  the window would cover it.

### M-6. Custom header replaces the native key-hint header (`visuals.ts:74-84`)
- With `quietStartup:"header"`, native builds a `BuiltInHeader` with interrupt, clear/exit, `/`, `!` and
  "Ctrl+O … more" hints (`interactive-mode.js:715-765`). `setHeader` replaces it.
- **[C]** Ctrl+O still toggles expansion for tool cards. The header itself is static. The key hints are not
  visible anywhere.
- It is a deliberate trade for the workspace panel. Consider one hint row in the header, such as
  `Esc interrupt · Ctrl+O expand · / commands`.
- **[C]** The custom header does install: `builtInHeader` is created before `rebindCurrentSession`
  (`interactive-mode.js:762-787`), so `setExtensionHeader`'s early return (`:1981`) cannot swallow it
  at startup.

### M-7. PTY test blind spots and one residual race (`tests/pi/capability-ui.py`)
- **[E]** The 22:55 failure was a race: `ui_prompt_end` is emitted before the command handler records
  `answer`. It is fixed at `:135-137` and the fixture now records `answer ?? null`.
- **Race, [C]/[H].** `:158-162` waits for the `startup` record, then for `PRESERVED_STATUS` and a single
  editor row.
  - The `startup` record is written inside `session_start` (`fixture.ts:7-10`). That is before Pi finishes
    the reload and dismisses the reload box (`interactive-mode.js:5408-5440`).
  - `PRESERVED_STATUS` and the editor row are also true of the pre-reload screen. If no repaint has
    happened yet, the check passes without the new runtime being rendered.
  - The next `send('/reload\r')` or `send('VISUAL_AFTER_RELOAD\r')` can then land during reload. This is the
    same class as the flake that just failed.
  - **Fix:** use a per-generation status marker such as `PRESERVED_STATUS_<n>`, or wait for the
    `Reloaded keybindings…` status line.
- **The tool-panel assertion cannot tell Zentui panels from native cards.** `:124`
  (`count('visual-canary.ts') >= 2`) passes on native fallback. Zentui's `canOwn` can silently fall back on
  a future Pi or Zentui change. The screenshot shows Zentui panels today.
  - **Fix:** assert Zentui-specific strings such as `↳ loaded 1 line` and `diff •`.
- **Not asserted:**
  - Hidden startup resource listing. I confirmed in `raw.ansi` that there is no `[Extensions]`, `[Skills]` or
    `[Context]` and no diagnostics, but nothing pins it.
  - Exactly one `PI WORKSPACE` and one `CONTEXT` footer line after each reload.
  - Transcript user-frame and tool-card rendering after reload.
  - Anything on the 40-column screen (`:130` only writes `narrow.txt`). Not crashing is the only guarantee.
- **[E]** In the narrow capture, header, panels and footer fit cleanly with no overflow.

### M-8. Lifecycle evidence covers only `/reload` and `/quit`
- `new`, `resume` and `fork` are supported by code reading, not execution.
- **[C]** `session_shutdown` handlers run before `beforeSessionInvalidate`/`resetExtensionUI`
  (`agent-session-runtime.js:104-111`). `ctx` getters are live and assert active
  (`runner.js:613-690`). Both Pi and visuals tear down header and footer. Visuals' `dispose` unsubscribes
  `onBranchChange` and removes the TUI from `views`.
- **[C]** Extensions are re-instantiated: `createRuntime` builds a fresh session and runner
  (`agent-session-runtime.js:130-150`). I see no stale-ctx or duplicate-ownership path.
- No actual `/new` or `/resume` was run.

### M-9. TODO.md omits the new exceptions (`TODO.md:5` is the only Zentui entry)
- `AGENTS.md` asks for an entry on out-of-norm exceptions. The new ones are:
  - The local `visuals.ts` that wraps Zentui with a Proxy that no-ops `registerCommand`/`registerShortcut`
    and throws on `registerTool`.
  - Zentui's `UserMessageComponent` prototype patch (`user-message.ts:331-392`), which the spec originally
    excluded.
  - Zentui's `registerToolRenderer` resolver.
- Each needs a reason, an upstream link, an obsolescence check (for example a native Pi theme/footer hook or
  a Zentui release with a public footer opt-out) and the target config.
- Also note the upgrade hazard. A Pi or Zentui version that changes the `UserMessageComponent` export or
  `render` shape fails visibly, in the editor or user-message path, not unsafely.

## Verified safe (positive findings)

- **Proxy semantics [E]** (`probe.out:1-4`):
  - `registerTool` throws `Visuals must not replace tool execution`.
  - `registerCommand` and `registerShortcut` return undefined and are swallowed.
  - `on` passes through.
  - **[C]** Zentui 0.32.0 never calls `registerTool`. Its tool panels use `registerToolRenderer`. A future
    Zentui that registers tools makes the extension fail loudly at load, not silently.
  - **[C]** Passthrough via `Reflect.get(target, key)` without a receiver works on Pi's closure-based API.
    The real PTY confirms it.
- **Single owner [C]:**
  - Zentui `footer.style="native"` only calls `setFooter(undefined)` when it owns the footer
    (`index.ts:1418-1430`).
  - No other managed extension calls `setFooter`, `setHeader` or `setEditorComponent`. I searched
    `dotfiles/pi`, pi-subagents 0.80.0 and the superpowers extension.
- **Source identity [E]:** the PTY asserts the builtin `read` and `edit` `sourceInfo` equals
  `builtin:<name>`. `requests.json` shows read, bash, edit, write, question, the five ast tools and
  `fetch_content`/`get_search_content` in all six requests. Rewrite and web_search are absent.
- **Preview preimage reads are bounded [C]** (zentui `pending.ts`): workspace-only, no symlinks, `O_NOFOLLOW`
  and `O_NONBLOCK`, 256 KiB cap, and only for rows whose arguments completed.
- **Statuses and lifecycle [E]:** `PRESERVED_STATUS` is rendered, and the status controller's visibility
  defaults to show. No `Extension error`, `Failed to load extension` or `stale after` appears in the
  raw stream (asserted at `:167`).
- **Footer rendering [E]** (`probe.out`, `probe2.out`):
  - No overflow for widths 1..200 with ASCII.
  - No overflow with wide-glyph model id and provider.
  - Header `panel` handles width < 8.
  - The only overflow is width 1 with two-column glyphs in a status, a degenerate case.
- **`ERROR`/`INTERRUPTED`/`NEEDS INPUT` states [C]:** derived from the final `stopReason` and the
  `ui_prompt_*` events.
- **Usage totals [E]:** summed over all session entries, as native does, including abandoned branches.
- **`quietStartup:"header"` [C]:** resource listing is hidden, and load diagnostics still show on reload
  (`interactive-mode.js:1062-1067,1327-1331,5423-5426`).
- **Theme [E]:** it loads (`events.json` theme name is `managed-opencode`), and `raw.ansi` has no theme warnings.
- **Config immutability [E]:** `:163-165` asserts the managed files remain symlinks with identical bytes.
- **I-1 (AST) fix [E]:** `ast-grep 0.51.0 --help` documents `--custom-languages` (default `ignore`), so
  the explicit flag is valid. The `config` schema removal plus execute refusal matches the nested test.
- **I-2 (wrapper) fix [C]:** `pi.nix:19-22` defaults only when the variable is unset or empty. The
  tested behaviour is default, empty, and explicit preserved. The change is intentional: an ambient
  `PI_CODING_AGENT_DIR` now redirects Pi off the managed agent directory by design.

## Declined to judge

- **Real Tuios terminal emulation.** The PTY uses pyte. Real Tuios was used only for hook parsing. I did not
  test Tuios's handling of the OSC 133 markers Zentui emits (18 in `raw.ansi`) or other OSCs
  (`\x1b]7501;`). Confirm interactively.
- **Real provider usage and cache payloads** (llm-platform through Headroom) for IN/OUT/CACHE.
- **Zentui panels beyond read and edit:** bash, write, grep, find, ls, MCP, custom and `question` renderers.
  `bash` ownership depends on renderer identity matching. I did not test it.
- **Real `/new`, `/resume`, `/fork` runs, and subagent children.** I did not check whether children load
  `visuals.ts` from `settings.json`. If they do, the `ctx.mode !== "tui"` guards and Zentui's TUI checks
  should make it a no-op.
- **Real-home activation beyond the symlink and settings observation.** No inference or daemon work.
- **Long-session performance.** `refresh` is O(entries) on `tool_result`.
- **Light or non-truecolor terminals, short terminals and tmux panes.** The theme is dark only.
- **Whole Zentui source.** Roughly 30k lines; I read only the tool-display, user-message, prototype-patch,
  footer and lifecycle paths. No dependency lock re-audit.
- **I-3 URL data-egress.** The user explicitly accepted it. I did not add or propose an allowlist.
- **No `ce-compound` note.** This was a read-only review.
