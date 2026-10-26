---
title: Pi web search fails over across providers and keeps its key out of the policy because the wrapper requires an exact policy match
date: 2026-10-23
last_updated: 2026-10-25
category: tooling-decisions
module: modules/home-manager/pi/capabilities.nix
problem_type: tooling_decision
component: tooling
severity: medium
applies_when:
  - "Changing web_search providers, adding an API key, or loosening the web tool surface"
  - "A Pi session claims it has no web search or falls back to scraping a search engine through fetch_content"
  - "Writing tests that drive the real web_search tool"
retire_when: "pi-web-access supplies keys and provider policy without requiring them in web-search.json, or Pi gains a native search tool"
tags: [pi, web-search, exa, pi-web-access, sops, home-manager, capabilities, cooldown]
---

# Pi web search fails over across providers and keeps its key out of the policy because the wrapper requires an exact policy match

## Context

`local.pi.capabilities.web` originally registered only `fetch_content` and `get_search_content`, with `webSearch.enabled = false`. `fetch_content` fetches a URL; it cannot search, and scraping a search engine through it hits bot checks (DuckDuckGo returned a challenge page). The missing search was a deliberate policy, not a harness gap.

## Update

Exa's free MCP returns 429 under load, which ended search entirely. `webPolicy` now allows `exa`, `parallel-mcp`, `keenable` and `duckduckgo` and sets `searchRouting.providers` in that order with `fallbackOn = [transient, quota, network, invalid-response]`. The last three are explicit-only upstream, so they must be named in `searchRouting` (the allowlist alone never selects them). Keenable's public endpoint needs no key; DuckDuckGo stays last because it blocks scrapers intermittently. Provider choice remains policy-only, never model-selected. Ceramic needs a key and is excluded. Policy contract: `tests/pi/capabilities-contract.mjs`.

Post-switch verification on 2026-10-25 loaded the installed wrapper in a fresh process with a temporary agent directory and no API credentials. An unmodified live search received an Exa HTTP 429 and returned Parallel results. Injecting 429 responses for Exa and Parallel reached live Keenable results; injecting them for the first three reached live DuckDuckGo results. All successful cases remained readable through `get_search_content`. Injecting 429 for all four returned an explicit routing-exhausted error. These exercised the real tool implementations through a standalone registration harness, not a model-driven session.

Upstream has no cooldown for these providers: two consecutive calls in the same process both attempted Exa before falling through to Parallel. `dotfiles/pi/extensions/search-cooldown-core.ts` therefore wraps `globalThis.fetch` for the five provider hosts: after a 429 (cooldown from `Retry-After`, 5 to 300 s, default 60 s) or a 402 (ten minutes) it answers locally with a 429, the status upstream classifies as quota, so the next provider is tried without a round trip. Verified with a keyed fake Exa returning 402 and then 429: the first query reaches Exa once and is served by Parallel, the second never contacts Exa.

The Exa key is the SOPS secret `exa_api_key`. Upstream asks the paid API when a key resolves and the keyless MCP when none does, and a policy value, including a `!command`, always resolves, so a key in the policy can never fall back to the MCP (an empty command output is a credential error that stops search). The wrapper is therefore given only the secret's runtime path (`installWebAccess(..., { exaKeyFile })`), reads it per search, and sets `EXA_API_KEY` for the duration of that search, but not while the API host is cooling down or when the file cannot be read. That makes Exa fall back to its keyless MCP after a 402 (`NO_MORE_CREDITS`, [Exa error codes](https://docs.exa.ai/reference/error-codes)) or a 429, and a missing secret degrade to keyless instead of failing. Free credit resets monthly per [Exa's rate-limit docs](https://exa.ai/docs/reference/rate-limits), so the API is retried after each ten-minute cooldown. Verified with the real wrapper, a synthetic key file and a fake Exa API answering 402: the first query reaches the API once with the file's key, the second asks `mcp.exa.ai` and then Parallel, the third skips both Exa hosts, and `EXA_API_KEY` is never left in the environment. Upstream classifies a 401 or 403 as `auth`, which is not an allowed `fallbackOn` kind and would end the search, so the cooldown wrapper answers those from any provider host with a 429 (dropping the provider's body, which may echo a credential) and cools the host for ten minutes; a revoked key then reaches the keyless MCP and Parallel like a spent credit. Verified with the real wrapper and a fake Exa API answering 401 and 403. The `web_search` guidelines also tell the model to report a total failure instead of scraping a search engine through `fetch_content`, which is how DuckDuckGo's bot block was first hit. The checked-in loopback profile passes no key file, because the build sandbox has no secret.

## Guidance

- Search is enabled through `webPolicy` in `modules/home-manager/pi/capabilities.nix`: the four-provider allowlist and matching ordered `searchRouting.providers` select keyless failover, while `tools.sourceCheck.enabled = false` keeps the tool surface narrow. No search credential enters the Nix store.
- `dotfiles/pi/extensions/web-access.ts` compares `web-search.json` to the Nix policy with deep equality before load and before every call. So a key cannot be written into the policy file, and a sops-rendered file would fail the comparison. Pass the secret's runtime path to the wrapper instead (see Update). Upstream also reads `EXA_API_KEY` and `EXA_BASE_URL` from the environment, which would send queries wherever those point.
- The wrapper exposes only `query`/`queries` (at most 4, 400 chars each), `numResults`, `recencyFilter`, `domainFilter`, `category`, and forces `workflow: "none"`. `provider`, `proxy`, `includeContent` and the curator workflows are refused.
- `web_search` results carry their `responseId` in the text, not in `details`, and `get_search_content` needs `queryIndex` to read a search. Assert on the text and pass `queryIndex: 0`.
- Tests drive the real provider code in the loopback profile by setting `EXA_API_KEY` and `EXA_BASE_URL=http://127.0.0.1:<port>` against a fake `POST /search` server. Upstream accepts plain HTTP only for loopback hosts. The production profile never executes a search in the sandbox; it checks the schema, refused arguments and tamper refusal.

## Why This Matters

Reversing the earlier fetch-only decision widens data egress: queries go to the selected allowed provider and a prompt-injected model can place local data in a query. Query length and count caps reduce this but are not an egress control (`docs/pi.md`).

## When to Apply

- Before adding a provider, key or tool to the web profile.
- When a session reports that search is unavailable: check `webSearch.enabled` in the generated `~/.pi/agent/web-search.json` first.

## Examples

Verified on Framework (`homeConfigurations.cachyos-framework13`): `pi-capabilities`, `pi-capabilities-loopback`, `pi-capabilities-contract`, `pi-base`, `pi-routing`, `pi-headroom` and the rest of the `pi-*` checks pass, and a direct JSON-RPC call to `https://mcp.exa.ai/mcp?tools=web_search_exa` returned results without a key.

## Related

- `dotfiles/pi/extensions/web-access.ts`
- `docs/pi.md` (web profile and data-egress notes)
- `TODO.md` (`local.pi.capabilities` exception entry)
