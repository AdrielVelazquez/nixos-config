---
title: OpenCode Go and Zen providers - key handling, free models, and model IDs
date: 2026-10-21
category: tooling-decisions
module: modules/home-manager/opencode-go.nix
problem_type: tooling_decision
component: tooling
severity: medium
applies_when:
  - "Adding or changing opencode-go or opencode models in a host's routing.agents"
  - "Choosing a free OpenCode model for background agents such as explore or title"
  - "Connecting the OpenCode console account or an API key on a host"
retire_when: "OpenCode changes how the opencode and opencode-go providers read OPENCODE_API_KEY or enable free models, or the Go and Zen docs change their free-model lists, limits or privacy terms; reread opencode.ai/v2/docs/console/go and /console/models and rerun the standalone model listing in the Examples section"
tags: [opencode, opencode-go, zen, free-models, sops, api-key, privacy, home-manager]
last_updated: 2026-10-21
---

# OpenCode Go and Zen providers - key handling, free models, and model IDs

## Context
The Razer routes agents to the OpenCode Go subscription (`opencode-go/<id>`) and to free models on the pay-as-you-go gateway, Zen (`opencode/<id>`). The docs describe each product separately and do not say how the two interact in the client, so the behavior below comes from the docs, `models.dev` and the pinned OpenCode source.

## Guidance
- **Connecting the console account makes paid Zen models selectable.** After the console login the `opencode` provider listed 41 models including `gpt-6.1-sol` and `claude-sonnet-5-5`, and after logout it listed only the 10 free ones. The same happens with `OPENCODE_API_KEY`, and the paid ones bill console credits.
- **Free is not the same product as Go.** Go's free models are MiniMax M3.1 Flash Free, LongCat 2.5 Preview Free and Beam Free. DeepSeek V4.1 Flash Free and GLM-5.3-Flash Free are Zen-only. All are limited-time. Zen documents zero retention and no training for DeepSeek V4.1 Flash Free, GLM-5.3-Flash Free, MiniMax M3.1 Flash Free and LongCat 2.5 Preview Free, but Big Pickle, Exo, MiMo Free and the Nemotron free endpoints may use or log prompts. Go's Gemini 4 Argon and Muse Spark Contributor models train on your data.
- **Go limits are per-model dollar caps, not request counts.** On the $10 plan DeepSeek V4.1 Flash has an $80 monthly cap, about 173k requests, while Kimi K3 has $15, about 490 requests. The 5-hour cap is 20% of the monthly one. Cheap models in the agent's hot loop last; expensive ones suit `plan`.
- **Verify IDs without a real key.** `OPENCODE_API_KEY=unused opencode models --standalone` lists the full Go catalog from a private server. The `models.dev` Go list lags the docs, so do not use it for IDs.
- **Go DeepSeek models need the workspace's Global region.** With the console workspace limited to US/EU, `opencode-go/deepseek-v4-pro` and `opencode-go/deepseek-v4.1-flash` fail with "This Go model requires Global regions. Select Global in your workspace's Privacy settings to use it." The setting is in the Console, not the client, at `https://opencode.ai/console/<workspace-id>/settings/privacy` (also Settings → Privacy for owners and admins with a Go subscription), alongside a training toggle for paid models that train on prompts. Docs do not say where Global requests are processed. The free Zen `opencode/deepseek-v4.1-flash-free` works from US/EU. Tested working from a US/EU workspace on 2026-10-21: Kimi K2.7 Code, GLM-5.3, GLM-5.2, GLM-5.3-Flash, MiMo-V2.6-Pro, MiniMax M3, Qwen3.8 Max and LongCat-2.0.
- **Variants come from the connected catalog.** With the console login connected, the model list shows each model's real variants: `glm-5.3` and `glm-5.3-flash` offer `low`, `high` and `max`, `deepseek-v4.1-flash-free` offers `low`, `high` and `max`, and `kimi-k2.7-code` has none. An unknown variant fails model resolution.
- **No credential still gives free Zen models.** The `opencode` provider activates with the placeholder key `public` and enables only models that cost nothing (`packages/core/src/plugin/provider/opencode.ts`).
- **Either a console login or `OPENCODE_API_KEY` connects both providers.** `models.dev` lists `OPENCODE_API_KEY` as the env var for `opencode` and `opencode-go`. A console login through `/connect` or `opencode auth login` also works and was verified against Go models. The login is stored in the local OpenCode database, so it is a manual per-machine step, not something Nix manages.

## Why This Matters
A single env var silently widens which paid models are selectable, free models differ in who may train on your prompts, and a model ID that looks right can still fail resolution. None of that shows in the Nix module.

## When to Apply
- Before adding any `opencode/` or `opencode-go/` model to a mapping.
- Before treating a free model as safe for private code.
- When the Go model list or limits change.

## Examples
Checked on 2026-10-21 against opencode.ai/v2/docs/console/go and /console/models. To re-list the Go catalog, run `OPENCODE_API_KEY=unused opencode models --standalone | grep -A40 '^opencode-go'`.

## Related
- `modules/home-manager/opencode-go.nix`
- `users/adriel/default.nix` (Razer agent models)
- `docs/solutions/tooling-decisions/opencode-v2-agent-model-routing-semantics.md`
