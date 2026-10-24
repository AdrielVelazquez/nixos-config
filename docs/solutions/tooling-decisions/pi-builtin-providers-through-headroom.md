---
title: Routing Pi's built-in providers through Headroom - the header omits /v1, credentials are per provider, and max_tokens is renamed
date: 2026-10-23
category: tooling-decisions
module: modules/home-manager/headroom-pi-providers.nix
problem_type: tooling_decision
component: tooling
severity: medium
applies_when:
  - "Adding a built-in Pi provider (opencode-go, opencode, or another) to local.headroom.pi.providers"
  - "A Headroom-routed Pi request reaches the upstream at a doubled /v1/v1 path, or a model errors only through the proxy"
  - "Testing that Pi refuses to send inference when the proxy or launcher is missing"
retire_when: "Pi ships native per-provider proxy routing, or Headroom stops appending /v1/chat/completions to x-headroom-base-url or renaming max_tokens; reread headroom/proxy/handlers/openai.py and Pi's dist/core/provider-composer.js on each bump and rerun checks.pi-headroom-providers"
tags: [pi, headroom, opencode-go, opencode, registerprovider, x-headroom-base-url, max-tokens, razer]
last_updated: 2026-10-23
---

# Routing Pi's built-in providers through Headroom - the header omits /v1, credentials are per provider, and max_tokens is renamed

## Context
Headroom's Pi launcher only had the LLM Platform adapter, whose provider extension reads the proxy contract. Razer's Pi uses Pi's built-in `opencode-go` and `opencode` providers, which have no such extension. `local.headroom.pi.providers` fills that gap, and the facts below came from running real Pi against the real proxy rather than from the docs.

## Guidance
- **The hook is `pi.registerProvider(id, { baseUrl, headers })` with no `models`.** Pi keeps the built-in models and replaces their `baseUrl` (Pi 1.3.0's provider composer applies `config.baseUrl ?? model.baseUrl`). Extension registrations are applied after `models.json`, which the launcher-less test relies on.
- **`x-headroom-base-url` is the upstream base without its trailing `/v1`.** Headroom appends `/v1/chat/completions` (or `/v1/responses`) itself (Headroom 0.37.0's OpenAI handler, `_resolve_openai_handler_path`). Sending the catalog's `https://opencode.ai/inference/go/v1` produced `/inference/go/v1/v1/chat/completions`. A sub-path in the header is preserved, while `HEADROOM_ALLOWED_BASE_URLS` matches by origin, so `headroom.ts` attributes by `new URL(header).origin`.
- **Fail closed with a dead address, not by doing nothing.** A built-in provider goes direct when the extension registers nothing, so the refused branch registers `http://127.0.0.1:1/headroom-required`. A test that starts Pi without the launcher passes vacuously offline unless a `models.json` points the built-in provider at the fake gateway; only then does a fail-open regression fail it.
- **`max_tokens` becomes `max_completion_tokens`.** Pi's catalog selects `max_tokens` for GLM, Kimi and DeepSeek on these providers and Headroom renames it unconditionally (`_normalize_openai_max_tokens`). The fixture pins the rename. Whether the OpenCode gateway honours the new field is unverified live.
- **Credentials are per provider, and Nix can supply them.** `opencode` and `opencode-go` each use `envApiKeyAuth`, so `/login` stores one credential per provider, while `OPENCODE_API_KEY` in the environment covers both. `local.pi.apiKeys` instead writes a read-only `models.json` whose `apiKey` is `!cat <sops secret path>`; Pi trims the output, counts a command key as configured (a missing secret is an authentication error on the first request, not `Unavailable model`), and a `/login` credential still wins over it. sops-nix fails every secret's install when a declared key is missing from the file, so the wiring is guarded on the key existing. OpenCode v2's `opencode` integration also offers an OAuth device login (`auth login opencode --method device`) while `opencode-go` lists only `key`; Pi has OAuth for neither.
- **Only chat-completions models are routed correctly.** Anthropic- and Google-API models in those catalogs have bases without `/v1`, so the provider-wide `baseUrl` makes them hit `/v1/v1/messages` and fail with an error, never directly.
- **Thinking levels follow the catalog.** A `null` entry in `thinkingLevelMap` means unsupported: GLM-5.3, GLM-5.3-Flash and the free DeepSeek accept `low`, `high` and `max`; `kimi-k2.7-code` has no map and runs `:off`, which omits `reasoning_effort` rather than disabling thinking.

## Why This Matters
Each of these fails quietly or looks right in the Nix: a doubled path 404s, a missing credential surfaces as a model-availability error, and a fail-open provider still "works" while bypassing compression. `checks.pi-headroom-providers` and `checks.pi-razer` encode the verified parts.

## When to Apply
- Before declaring another provider in `local.headroom.pi.providers` or changing a Razer role selector.
- When bumping Pi or Headroom.

## Related
- `docs/solutions/tooling-decisions/opencode-go-and-zen-provider-setup.md`
- `TODO.md` (the Razer Headroom routing entry lists the live recheck)
- `docs/pi.md` (Razer section)
