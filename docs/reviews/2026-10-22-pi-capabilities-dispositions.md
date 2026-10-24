# Sonnet review dispositions

Complete original report: [2026-10-22-pi-capabilities-sonnet.md](2026-10-22-pi-capabilities-sonnet.md).
Reviewer: `llmplatform/claude-sonnet-5-5#xhigh`; reviewed through `9b792cc`.
No Critical findings. User explicitly activated that revision while review was
pending; later fixes/visuals are not assumed active until another approved switch.

## Important

- **I-1 fixed:** removed `ast_grep_scan.config` from advertised schema and refused
  it at execution; pinned `--custom-languages ignore` as well as the empty config.
  Updated scan guidance. Actual SDK schema/nested regression failed before the
  fix and passed after it; both production and loopback profiles pass.
- **I-2 fixed:** managed directory is a default, not an unconditional override.
  Test runs the actual generated wrapper with a harmless substituted launcher,
  synthetic token and default/empty/explicit directory cases; RED→GREEN.
- **I-3 documented and explicitly accepted by user (2026-10-22):** local-read plus arbitrary
  public fetch can send data in URL paths/queries, including following prompt
  injection. Read-only is not an exfiltration boundary. Docs/TODO now state this;
  no domain allowlist or secret-file firewall is claimed. The user chose
  “Activate; keep web fetch” after the URL data-egress risk was stated explicitly.

## Minor findings

- **M-1 deferred:** upstream outline can create an unreported second spill.
  Do not call upstream's global cleanup on each in-process child shutdown: it
  could delete another active session's spills. A per-session upstream API is
  preferable. Current cleanup only promises tracked spill ownership.
- **M-2 deferred:** catalog/wire absence checks are discriminating; execution-only
  unpreviewed-rewrite witnesses are weaker. No rewrite is registered.
- **M-3 deferred:** production generated child declaration could use a stronger
  explicit id assertion; configuration and actual async child snapshots already
  assert the two required capabilities.
- **M-4 deferred:** actual explore web/Code Mode rejection is not directly probed;
  configured role ceilings and underlying generic Code Mode refusals are tested.
- **M-5 documented:** broadened private-range claims softened; upstream IPv6
  transition/embedded-form gaps and DNS rebinding are explicit TODOs, not fixed.
- **M-6 partly addressed:** scan description now matches the fixed config policy;
  broader upstream language/help and scout MCP-only wording remain follow-ups.
- **M-7 retained:** scrubbing package-specific cookie opt-in environment variables
  is a process-wide defensive choice; no other configured consumer relies on them.
- **M-8 deferred:** missing fixed binary failure is true by construction but lacks
  its own direct witness; hostile ambient binary selection is covered.
- **M-9 resolved operationally/documented:** approved first activation passed
  checkLinkTargets without clobbering files; on-disk cache/TTL/size now documented.
- **M-10 addressed by new scope:** actual model turn renders read/edit panels;
  actual question tool/free-form input, native AST status, repeated reload and
  Tuios parsing are tested. Mutable skin menus/shortcuts are no longer registered.
- **M-11 deferred:** adapters rely on exact source pins and real runtime checks;
  a separate TypeScript/lint gate is not added in this increment.
- **M-12 retained:** unrelated untracked `.serena/` is untouched. Interactive
  ast-grep remains available; this is not an OS sandbox for user-entered commands.

## Declined-to-judge dispositions

- Live credentials/provider and real daemon interaction: reserved for user live
  testing; no inference/daemon restart performed by implementation tests.
- Original full suite/build: parent verified 13/13 outputs and exact Framework/
  Razer evals before approved activation. Expanded visuals get a fresh full run.
- Non-editor visuals: user subsequently requested them; implemented and covered
  by real streamed PTY/tool/question tests plus a separate visual-delta review.
- Real-home conflicts: first activation succeeded. Future regular-file conflicts
  must still stop rather than be forced. No real ast-grep trust state was inspected;
  explicit ignore mode no longer relies on it.
- IPv6 host routing: no real network exploitation attempted; no stronger isolation claim.
- Other agent branch and rejected permission/LSP/Lens packages: deliberately untouched.
- Whether scout should fetch: user explicitly chose to retain it after disclosure;
  this is risk acceptance, not an added security guarantee.

## Full visual delta review

Complete second report: `2026-10-22-pi-visuals-sonnet.md`, same explicitly requested
Sonnet 5.5 xhigh model. No Critical issues.

- **Visual I-1 fixed:** subscribe to native `thinking_level_select`. A real PTY
  regression changed thinking while idle and showed the stale footer before the
  fix; it passes afterward. Existing `/plan`/`/build` routing stays unchanged.
- **Visual M-9 documented:** TODO now records the Proxy, upstream private message
  patch and public tool renderer resolver with links/removal gates/target.
- **Visual M-3 docs corrected:** only unknown context is guaranteed to show a dash;
  absent token/cache fields can appear as zero. No billing accuracy claim added.
- **Visual M-1/M-2/M-4/M-5/M-6/M-7/M-8 deferred:** footer-height bounds, C1/bidi
  sanitization, provider-specific proxy-health indication, remaining layout/context
  warning cosmetics, key hints, stronger generation-specific repaint/fallback
  witnesses and real new/resume/fork coverage remain listed in the full report.
  The user subsequently chose to evaluate native OMP instead of further Pi skin
  refinement. None changes tool execution or authorizes secret/network bypass.
- Declined live Tuios terminal handling, provider usage semantics, additional tool
  panels, long-session performance and other terminal types remain user trials or
  future targeted tests; no synthetic test is presented as proof of those cases.
- Parent independently verified the final 14-output suite before the new OpenCode/
  OMP scope began, and recorded exact activated generation and user consent.
