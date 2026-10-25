---
title: Pi tool use is steered by tool descriptions and promptGuidelines, and SYSTEM.md would delete them
date: 2026-10-25
category: tooling-decisions
module: dotfiles/pi/extensions/web-access.ts
problem_type: tooling_decision
component: tooling
severity: medium
applies_when:
  - "A Pi agent underuses a tool that is registered and working, such as web_search"
  - "Considering SYSTEM.md, APPEND_SYSTEM.md, or porting another harness's system prompt into Pi"
  - "Adding behavioral guidance to dotfiles/pi/AGENTS.md or asserting on its rendered text"
retire_when: "Pi changes how buildSystemPromptSections handles a custom prompt or promptGuidelines; compare dist/core/system-prompt.js and docs/configuration.md in the new pi-coding-agent before relying on this"
tags: [pi, system-prompt, prompt-guidelines, web-search, agents-md, opencode, configuration-contract]
---

# Pi tool use is steered by tool descriptions and promptGuidelines, and SYSTEM.md would delete them

## Context

Pi searched the web less than OpenCode did, on the same default model (`gpt-6.1-sol:high`). A captured Pi session (the `system` entry in `~/.pi/agent/sessions/*.jsonl`) showed why. `web_search` was one line of the `<tools>` list ("Use for web research. Prefer {queries:[...]}..."), the `<rules>` section had about 26 bullets and none concerned the web, and nothing in the 33 KB prompt mentioned a knowledge cutoff, the date, or checking claims. OpenCode's `websearch` description (in the pinned OpenCode source, an external repo) says to use it for information beyond the knowledge cutoff and states the current year.

The size is not the difference. OpenCode's own `gpt.txt` is about 2.5 KB and does not mention search either. What differs is content and placement: Pi's prompt is mostly tool mechanics, OpenCode's mostly behavior, and OpenCode's tool descriptions carry a "when to use" trigger.

## Guidance

- Steer a tool through its `description` (when to use it) and `promptGuidelines` (rules in the system prompt), both set in `registerTool`. `promptSnippet` only fills that tool's line in `<tools>`. `web-access.ts` overrides all three for `web_search` and `fetch_content`; the upstream `pi-web-access` text had no "when" trigger either, so it was inherited rather than introduced.
- Put cross-tool behavior in `dotfiles/pi/AGENTS.md` (`programs.pi-coding-agent.context`, set in `modules/home-manager/pi/workflow.nix`). The `# Evidence` and `# Working style` sections port OpenCode's behavioral prompt and leave out what contradicts Pi: the `oldString`/`newString` edit guidance (Pi edits by hashline anchor), `<system-reminder>` blocks, and the OpenAI "commentary channel" wording.
- Do not use `SYSTEM.md`. With a custom prompt, `buildSystemPromptSections` emits only the preamble and drops `<tools>`, `<rules>` and `<docs>`, which deletes every per-tool guideline. `APPEND_SYSTEM.md` is safe, but a trusted project's own `APPEND_SYSTEM.md` (in that project's `.pi` directory) replaces the global file instead of merging with it, whereas global and project `AGENTS.md` both reach `<project_context>`.
- Tests: `tests/pi/capabilities.mjs` asserts the real `getAllTools()` description and `promptGuidelines` for the web tools, and the `configuration-contract` entry in `checks.nix` asserts phrases in the rendered context. Those phrases are plain substring checks, so a phrase wrapped across two lines in `AGENTS.md` fails; this happened with "comment density". Keep asserted phrases on one line.
- `tests/pi/configuration.py` is not run by any Nix check and was already stale (it asserts that razer14 has Pi disabled). Do not use it as a gate.
- Not established: no A/B shows the new guidance raises search use. Since `web_search` shipped on 2026-10-23, 4 of 14 Pi sessions used it, against 11 of 47 OpenCode sessions in this repo, with different workloads and small samples.

## Why This Matters

Registering a tool does not make the model use it. Copying OpenCode's prompt wholesale would add edit instructions that contradict the hashline tools, and routing through `SYSTEM.md` would silently remove the guidelines that make Pi's other tools work. More searching also sends more queries to Exa; see the egress notes linked below.

## When to Apply

- A registered Pi tool is rarely called: check its description and `promptGuidelines` in the captured system prompt before changing models or adding tools.
- Before adding `SYSTEM.md` or `APPEND_SYSTEM.md` to the Nix-managed agent directory.
- When adding contract phrases for `AGENTS.md` text.

## Examples

Verified on Framework (`homeConfigurations.cachyos-framework13`): `configuration-contract`, `pi-capabilities`, `pi-capabilities-loopback` and `pi-capabilities-contract` pass, and the exact Framework Home Manager and `nixosConfigurations.razer14` evaluations succeed. The new assertions failed first, for the expected reason: the web description lacked the trigger, and the context lacked the new sections.

## Related

- `dotfiles/pi/extensions/web-access.ts`
- `dotfiles/pi/AGENTS.md`
- `docs/solutions/tooling-decisions/pi-web-search-exa-only-policy.md` (egress and policy)
