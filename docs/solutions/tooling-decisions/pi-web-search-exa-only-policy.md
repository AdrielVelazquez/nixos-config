---
title: Pi web search is Exa-only and secret-free because the wrapper requires an exact policy match
date: 2026-10-23
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
tags: [pi, web-search, exa, pi-web-access, sops, home-manager, capabilities]
---

# Pi web search is Exa-only and secret-free because the wrapper requires an exact policy match

## Context

`local.pi.capabilities.web` originally registered only `fetch_content` and `get_search_content`, with `webSearch.enabled = false`. `fetch_content` fetches a URL; it cannot search, and scraping a search engine through it hits bot checks (DuckDuckGo returned a challenge page). The missing search was a deliberate policy, not a harness gap.

## Guidance

- Search is enabled through `webPolicy` in `pi-capabilities.nix`: `webSearch.allowedProviders = ["exa"]`, `searchProvider = "exa"`, `tools.sourceCheck.enabled = false`. Exa's hosted MCP needs no credential, so nothing secret enters the Nix store.
- `dotfiles/pi/extensions/web-access.ts` compares `web-search.json` to the Nix policy with deep equality before load and before every call. So a key cannot be added to the policy file without changing the expected policy too, and a sops-rendered file would fail the comparison. If the keyless MCP rate-limits (429), find a runtime key route that leaves the managed file untouched; upstream also reads `EXA_API_KEY` and `EXA_BASE_URL` from the environment, which sends queries wherever those point.
- The wrapper exposes only `query`/`queries` (at most 4, 400 chars each), `numResults`, `recencyFilter`, `domainFilter`, `category`, and forces `workflow: "none"`. `provider`, `proxy`, `includeContent` and the curator workflows are refused.
- `web_search` results carry their `responseId` in the text, not in `details`, and `get_search_content` needs `queryIndex` to read a search. Assert on the text and pass `queryIndex: 0`.
- Tests drive the real provider code in the loopback profile by setting `EXA_API_KEY` and `EXA_BASE_URL=http://127.0.0.1:<port>` against a fake `POST /search` server. Upstream accepts plain HTTP only for loopback hosts. The production profile never executes a search in the sandbox; it checks the schema, refused arguments and tamper refusal.

## Why This Matters

Reversing the earlier fetch-only decision widens data egress: queries go to Exa and a prompt-injected model can place local data in a query. Query length and count caps reduce this but are not an egress control (`docs/pi.md`).

## When to Apply

- Before adding a provider, key or tool to the web profile.
- When a session reports that search is unavailable: check `webSearch.enabled` in the generated `~/.pi/agent/web-search.json` first.

## Examples

Verified on Framework (`homeConfigurations.cachyos-framework13`): `pi-capabilities`, `pi-capabilities-loopback`, `pi-capabilities-contract`, `pi-base`, `pi-routing`, `pi-headroom` and the rest of the `pi-*` checks pass, and a direct JSON-RPC call to `https://mcp.exa.ai/mcp?tools=web_search_exa` returned results without a key.

## Related

- `dotfiles/pi/extensions/web-access.ts`
- `docs/pi.md` (web profile and data-egress notes)
- `TODO.md` (`local.pi.capabilities` exception entry)
