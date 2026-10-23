# Audited upstream Pi capabilities

User authorization: after receiving the package audit, the user asked to implement
it now. This supersedes another design/plan approval pause, not activation consent.

## Scope

Framework Home Manager only: `homeConfigurations.cachyos-framework13` on CachyOS.
Keep upstream Pi 1.3.0, provider, mandatory Headroom, routing, Serena, native
questions and Tuios. Razer remains unchanged. Work independently of the other
agent's `feat/pi-feature-gaps` branch; do not reuse or modify its implementation.

- Pin `pi-zentui@0.32.0`. The initial editor-only increment was completed; the
  user subsequently explicitly requested the full visual mockup, not just the editor.
  Use a local dark/lavender theme, public-API workspace/model/mode header and
  context/cache/usage/status footer, Zentui copy-friendly framed messages and
  balanced builtin tool panels. Native question/input execution and existing
  extension/MCP renderers remain intact. No experimental thinking, selector
  prototype patches, working-line replacement, polling, quota or GitHub probes.
  Zentui does not own the footer; the local public-API visual extension is its
  single owner. No tool re-registration or mutable skin commands/shortcuts.
- Pin `@juvio15/pi-ast-grep@0.4.2` and Nix ast-grep. Register only five upstream
  read tools through its exported factory. Never register rewrite or its mutable
  rule commands. Pin the actual executable independently of ambient PATH/env.
- Pin `pi-web-access@0.44.0` with locked dependencies, lifecycle scripts disabled.
  HTTP-only readable/raw fetch and stored retrieval, no search/AI/cookies/media/
  PDF/cloning/curator. Remove model-callable proxy/auth/model/prompt/media knobs,
  reject extra arguments at execution, require the managed policy on every call.
- Native compaction remains native; no speculative token thresholds or extra
  compaction model. Existing Nix Go/gofmt stays the explicit formatter workflow.
- Reusable module with opt-in flags; Framework enables the three audited profiles.
  AST and fetch entries are mandatory in native children, but role allowlists
  still govern access: local explore has no web, scout has fetch/retrieval, and
  read-only roles gain no writer, shell, rewrite or delegated-writer capability.

## Boundaries

This is not the rejected permission engine, session-wide autonomy, an OS sandbox,
an LSP diagnostics replacement, or complete OMP parity. No rejected package,
subagent replacement, first-party LLMP scope, inference bypass or new secret.
No source patch to upstream packages. Public immutable package/config data alone
enters the store. Browser consent, live provider inference and activation remain
separately controlled. Do not switch or restart the live Tuios daemon.

## Acceptance

Real Pi loader/session tests: exact registered tools and schema, actual AST
search/outline, missing rewrite through nested and Code Mode, actual loopback
fetch/extraction/redirect negatives in a test-only private-range profile, production
loopback refusal, no side-model calls, immutable settings/policy links, policy
tampering fails closed, and missing binaries never install replacements.
Actual PTY tests: visible editor, paste/Unicode/mouse/resize, native questions,
Tuios parser states, footer status, repeated reload and unchanged managed files.
Compose capabilities with existing Headroom/provider and child routing tests.
Exact Framework/Razer evals, full Framework activation build and focused checks.
After implementation, adversarial review by `llmplatform/claude-sonnet-5-5#xhigh`;
deliver complete findings and dispositions, fixing important issues with regressions.
