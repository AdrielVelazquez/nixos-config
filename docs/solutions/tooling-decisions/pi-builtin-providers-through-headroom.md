---
title: Routing Pi's built-in providers through Headroom - the header omits /v1, credentials are per provider, and max_tokens is renamed
date: 2026-10-23
category: tooling-decisions
module: modules/home-manager/pi/headroom-providers.nix
problem_type: tooling_decision
component: tooling
severity: medium
applies_when:
  - "Enabling a built-in provider's local.headroom.pi.providers.<provider>.enable switch or adding a provider routing module"
  - "A Headroom-routed Pi request reaches the upstream at a doubled /v1/v1 path, or a model errors only through the proxy"
  - "Testing that Pi refuses to send inference when the proxy or launcher is missing"
retire_when: "Pi ships native per-provider proxy routing, or Headroom stops appending /v1/chat/completions to x-headroom-base-url or renaming max_tokens; reread headroom/proxy/handlers/openai.py and Pi's dist/core/provider-composer.js on each bump and rerun checks.pi-headroom-providers"
tags: [pi, headroom, opencode-go, openai-codex, registerprovider, x-headroom-base-url, max-tokens, razer]
last_updated: 2026-10-29
---

# Routing Pi's built-in providers through Headroom - the header omits /v1, credentials are per provider, and max_tokens is renamed

## Context
The original Pi launcher only routed LLM Platform, whose provider extension reads its proxy contract. Built-in providers need explicit endpoint overrides: inheriting `HEADROOM_PROXY_URL` does not route them. The original Go adapter was validated with real Pi against real Headroom; the protocol details below remain relevant after migrating the public configuration from a URL map to provider switches.

Current configuration uses `local.headroom.pi.providers.<provider>.enable` for `opencode-go`, `openai-codex` and `llm-platform`, with modules under `modules/home-manager/pi/headroom/`. Generic routes are contributed internally through `local.headroom.pi.routes`. Provider availability is independent: a disabled routing switch leaves direct inference intact; an enabled route must fail closed. The core permits all routing switches off so Headroom's MCP/session lifecycle does not implicitly force an inference adapter.

Codex cannot be treated as the ordinary OpenAI Chat route merely because both are OpenAI services. Pi's native `openai-codex` implementation builds a Codex Responses path and forwards runtime subscription authentication. `headroom-codex.ts` redirects only its base and routing headers to the proxy's Codex alias; it leaves native login, catalog, HTTP/WebSocket conversion and retries intact. `tests/pi/headroom-codex.mjs` exercises both transports and dashboard accounting with synthetic OAuth and a loopback backend. Headroom's external Codex endpoint constants are replaced only in the test process; no production authentication or routing handler is mocked. Live subscription acceptance remains a separate validation step.

LLM Platform's own optional proxy parser does not establish this repository's ownership policy: absent variables mean direct inference, and an arbitrary loopback URL is accepted. Its Nix-generated production entry therefore validates the enabled route before provider registration. For disabled routing it removes inherited proxy variables only while the upstream provider synchronously snapshots them, then restores the ambient environment before asynchronous Tool Registry setup. This boundary avoids leaking another session's temporary routing policy in SDK/native-child processes. `checks.pi-work` loads the actual packaged production provider, asserting its seed-model URLs for owned, absent, foreign, non-loopback and non-required contracts in both switch states. Recheck the synchronous-snapshot boundary on provider upgrades.

## Guidance
- **The hook is `pi.registerProvider(id, { baseUrl, headers })` with no `models`.** Pi keeps the built-in models and replaces their `baseUrl` (Pi 1.3.0's provider composer applies `config.baseUrl ?? model.baseUrl`). Extension registrations are applied after `models.json`, which the launcher-less test relies on.
- **`x-headroom-base-url` is the upstream base without its trailing `/v1`.** Headroom appends `/v1/chat/completions` (or `/v1/responses`) itself (Headroom 0.37.0's OpenAI handler, `_resolve_openai_handler_path`). Sending the catalog's `https://opencode.ai/inference/go/v1` produced `/inference/go/v1/v1/chat/completions`. A sub-path in the header is preserved, while `HEADROOM_ALLOWED_BASE_URLS` matches by origin, so `headroom.ts` attributes by `new URL(header).origin`.
- **Fail closed with a dead address, not by doing nothing.** A built-in provider goes direct when the extension registers nothing, so the refused branch registers `http://127.0.0.1:1/headroom-required`. A test that starts Pi without the launcher passes vacuously offline unless a `models.json` points the built-in provider at the fake gateway; only then does a fail-open regression fail it.
- **`max_tokens` becomes `max_completion_tokens`.** Pi's catalog selects `max_tokens` for GLM, Kimi and DeepSeek on these providers and Headroom renames it unconditionally (`_normalize_openai_max_tokens`). The fixture pins the rename. Whether the OpenCode gateway honours the new field is unverified live.
- **Credentials are per provider, and Nix can supply them.** `opencode` and `opencode-go` each use `envApiKeyAuth`, so `/login` stores one credential per provider, while `OPENCODE_API_KEY` in the environment covers both. `local.pi.apiKeys` instead writes a read-only `models.json` whose `apiKey` is `!cat <sops secret path>`; Pi trims the output, counts a command key as configured (a missing secret is an authentication error on the first request, not `Unavailable model`), and a `/login` credential still wins over it. sops-nix fails every secret's install when a declared key is missing from the file, so the wiring is guarded on the key existing. OpenCode v2's `opencode` integration also offers an OAuth device login (`auth login opencode --method device`) while `opencode-go` lists only `key`; Pi has OAuth for neither.
- **The base depends on the model's API protocol.** Pi's OpenAI-style clients append `/chat/completions` or `/responses`, and Google's follows the base unchanged, so those models keep `<proxy>/v1`. The Anthropic client appends `/v1/messages` itself: with `<proxy>/v1` as the base, Go's Anthropic-protocol models (`claude-haiku-5-5`, `minimax-m3`) were requested at `/v1/v1/messages` and opencode.ai answered with an empty-body 404 that Pi shows as "404 status code (no body)". `headroom-providers.ts` registers those models with the bare proxy as `baseUrl`, and `checks.pi-headroom-providers` sends one model per protocol and asserts the path the gateway receives.
- **Thinking levels follow the catalog.** A `null` entry in `thinkingLevelMap` means unsupported: GLM-5.3, GLM-5.3-Flash and the free DeepSeek accept `low`, `high` and `max`; `kimi-k2.7-code` has no map and runs `:off`, which omits `reasoning_effort` rather than disabling thinking.

## Why This Matters
Each of these fails quietly or looks right in the Nix: a doubled path 404s, a missing credential surfaces as a model-availability error, and a fail-open provider still "works" while bypassing compression. `checks.pi-headroom-providers` and `checks.pi-razer` encode the verified parts.

## When to Apply
- Before adding a provider routing module, enabling its switch, or changing a Razer role selector.
- When bumping Pi or Headroom.

## Related
- `docs/solutions/tooling-decisions/opencode-go-and-zen-provider-setup.md`
- `TODO.md` (the Razer Headroom routing entry lists the live recheck)
- `docs/pi.md` (Razer section)
