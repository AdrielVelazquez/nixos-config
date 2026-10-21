---
title: OpenCode V2 agent model routing - which agents honor `model`, and what not to route
date: 2026-10-21
category: tooling-decisions
module: modules/home-manager/opencode-routing.nix
problem_type: tooling_decision
component: tooling
severity: medium
applies_when:
  - "Adding or changing an agent-to-model mapping in local.opencode.routing"
  - "Considering a cheaper model for compaction or summary"
  - "Picking models for a host that has the Reddit LLM Platform catalog"
retire_when: "OpenCode V2 documents or implements agent-level model for the hidden summary agent, or the pinned opencode flake input changes how subagent, title, compaction or the TUI resolve agent.model; grep agent.model under packages/core/src and packages/tui/src in the input's source and reread opencode.ai/v2/docs/agents"
tags: [opencode, routing, agents, models, subagent, compaction, prompt-cache, llm-platform, home-manager]
last_updated: 2026-10-21
---

# OpenCode V2 agent model routing - which agents honor `model`, and what not to route

## Context
`local.opencode.routing.agents` maps agents to `provider/model#variant` strings and renders `agents.<name>.model` into `opencode.json`. The V2 agents page says only that "a subagent uses its configured model, or inherits the parent session's model". It does not say which built-in or hidden agents read an agent-level `model` at all. That had to be read from the pinned OpenCode source.

## Guidance
- **Honored:** subagents resolve `override ?? agent.model ?? parent.model` (`packages/core/src/tool/plugin/subagent.ts`). The hidden `title` agent uses `agent.model`, else the provider's small model (`packages/core/src/session/context.ts`). The hidden `compaction` agent uses `agent.model` unless the model uses native compaction (`packages/core/src/session/compaction.ts`).
- **Primary agents (`build`, `plan`) are honored by the TUI as the default for a new session, not by core.** In `packages/tui/src/context/local.tsx` the model for a new session is the last model chosen for that agent in that location, else `agent.model`, else the global default. An existing session keeps its stored model while its agent is unchanged. A saved per-model variant preference also beats the agent's configured `#variant`, which applies only when the agent's model matches. So a changed `build` mapping may not show up until that remembered choice is replaced.
- **Not honored:** nothing in `packages/core/src` reads the hidden `summary` agent's model, so routing it does nothing.
- **Do not route compaction to a cheaper model on the LLM Platform.** A different model cannot reuse the session's warm prompt cache, so compaction re-reads the whole context at the uncached input price. On 2026-10-21 `gpt-6.1-sol` cached input was $0.10 per million tokens, while uncached input was $0.75 for `gemini-3.8-flash` and $0.10 for `gpt-6-luna`. At best it breaks even, and quality drops.
- **V2 has no built-in `scout` agent**, so the module defines one as a read-only subagent.
- **Use catalog IDs as `opencode models` prints them.** The Framework default was `llmplatform/gpt-6-1-sol` while the catalog ID is `llmplatform/gpt-6.1-sol`, and there is no `gpt-6.1-luna`, only `gpt-6-luna` and `gpt-5.6-luna`. Variant names must also come from the model's catalog entry, for example `gpt-6-luna` offers `none` through `max` while `gemini-3.8-flash` offers only `low`, `medium` and `high`.
- **Source pricing and capabilities from `llmp model list --project <project> --format json`.** It lists price per million tokens, cached-input price, context window and reasoning efforts for every model the project can reach.

## Why This Matters
A mapping that looks complete can silently do nothing for `summary`, can be shadowed by a remembered TUI choice for `build` and `plan`, or can cost more than the session model for compaction. None of this is visible in the Nix module or the JSON it renders.

## When to Apply
- Before adding an agent to `routing.agents`.
- Before choosing a model for compaction.
- When a changed `build` or `plan` model does not take effect in an existing location.
- When a host's provider catalog changes and its models need refreshing.

## Examples
Verified on the Framework on 2026-10-21 with `opencode run --model <ref> "Reply with the single word: ok"`: `llmplatform/gpt-6-luna#low`, `llmplatform/gemini-3.8-flash#medium`, `llmplatform/gpt-6.1-sol` and `llmplatform/claude-sonnet-5-5#xhigh` each answered. To re-check which agents honor `model`, run `grep -rn "agent.model" packages/core/src` in the source of the `opencode` flake input.

## Related
- `modules/home-manager/opencode-routing.nix`
- `users/adriel-cachyos/default.nix` (Framework agent models)
