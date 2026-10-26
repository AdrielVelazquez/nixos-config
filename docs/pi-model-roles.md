# Pi model roles

Target config: `homeConfigurations.cachyos-framework13`. Validation host: Framework 13 / CachyOS x86_64-linux. Verification: `rtk nix eval .#homeConfigurations.cachyos-framework13.activationPackage.drvPath`, then `rtk nix build --no-link .#checks.x86_64-linux.pi-model-roles`. Razer: target `nixosConfigurations.razer14`, verified by `rtk nix build --no-link .#checks.x86_64-linux.pi-razer` (see the Razer section).

`local.pi.modelRoles.enable` installs a dependency-free router using Pi 1.3.0's public virtual-model API. Home Manager forces the initial model to `roles/auto`; it does not change the configured default thinking level. The previous primary `routing.ts` is removed. `local.pi.routing` now owns only the pinned subagent package, required-child integration policy and approved MCP tool lists.

## Defaults and consumers

Provider IDs are Pi's `llm-platform`, **not** omp's `llmplatform`.

The table lists the module defaults. Framework overrides them in `users/adriel-cachyos/default.nix`:

| Role | Framework selector | Note |
|---|---|---|
| default | `llm-platform/claude-haiku-5-5:high` | Conversation, `/build`; chosen from replay results in `moedl-routing-results.md` |
| plan | `llm-platform/claude-sonnet-5-5:high` | `/plan` |
| slow | `llm-platform/claude-sonnet-5-5:xhigh` | `/slow`, `ultrathink` |
| smol | `llm-platform/gpt-6-luna:low` | Pinned so it does not inherit Sonnet from `default` |
| commit, widget | `@smol` | Follow `smol` |
| tiny | `llm-platform/gpt-6-luna:low` | Automatic titles; managed `title` agent follows it |
| memory | `@tiny` | `/memory` |
| task | `llm-platform/gpt-6.1-sol:medium` | Exported task definitions only |
| advisor | `llm-platform/gpt-6.1-sol:high` | Different model family from the Sonnet conversation roles |
| vision | `llm-platform/gpt-6.1-sol:high` | Image-capable in the cached catalog |

The managed `build` subagent is `llm-platform/gpt-6.1-sol:medium` (`taskAgents.build`); `plan` follows the `plan`
role; `scout` and `explore` keep their module defaults. Selector thinking suffixes win over the global
`defaultThinkingLevel`.

## Razer

Razer has no LLM Platform, so `users/adriel/default.nix` sets every role and the `build`, `scout` and `explore` agents
on Pi's built-in `opencode-go` and `opencode` providers (reusing the models OpenCode already uses there). Provider IDs
are Pi's, not OpenCode's `#variant` syntax. Pi's catalog marks `null` for thinking levels a model does not accept, so
selectors use only accepted levels: `low`, `high` and `max` for GLM-5.3, GLM-5.3-Flash and the free DeepSeek, and `off`
for Kimi K2.7 Code, which has no variants.

| Role | Razer selector | Note |
|---|---|---|
| default | `opencode-go/kimi-k2.7-code:off` | Conversation, `/build` |
| plan | `opencode-go/glm-5.3:high` | `/plan` |
| slow | `opencode-go/glm-5.3:max` | `/slow`, `ultrathink` |
| smol | `opencode-go/glm-5.3-flash:low` | commit and widget follow it |
| tiny | `opencode-go/mimo-v2.6-flash:off` | Titles and `/memory`; cheap, image-capable, no thinking variants. No Zen or `-free` models: they are refused outside OpenCode |
| task | `opencode-go/kimi-k2.7-code:off` | Exported task definitions |
| advisor | `opencode-go/glm-5.3:high` | Different family from the Kimi conversation roles |
| vision | `opencode-go/kimi-k2.7-code:off` | GLM-5.3 is text-only |

Agents: `build` = Kimi, `plan` = `@plan`, `scout` = `opencode-go/glm-5.3-flash:low`,
`explore` = `opencode-go/mimo-v2.6-flash:off`, `title` = `@tiny`.

Razer enables `modelFallback`. A chain is looked up by the failed model, then `provider/*`, then the active role,
then `default`; these are keyed by role. Agents never fall back.

| Role | Fallback |
|---|---|
| default (also task) | `opencode-go/glm-5.2:high` |
| plan, advisor | `opencode-go/glm-5.2:high` |
| slow | `opencode-go/glm-5.2:max` |
| smol, commit, widget | `opencode-go/mimo-v2.6-flash:off` |
| tiny, memory | `opencode-go/glm-5.3-flash:low` |
| vision | `opencode-go/glm-5.3-flash:low` (GLM-5.2 is text-only) |

| Role | Default selector | Actual consumer |
|---|---|---|
| default | `llm-platform/gpt-6.1-sol:high` | Conversation, `/build` |
| plan | `llm-platform/claude-sonnet-5-5:xhigh` | `/plan` model and planning prompt |
| slow | `llm-platform/claude-sonnet-5-5:xhigh` | `/slow`, or `ultrathink` in the latest user message |
| smol | `llm-platform/gpt-6-luna:low` | Explicit conversation role/cycling |
| commit | `llm-platform/gpt-6-luna:low` | `/commit` drafts a message; never commits |
| memory | `llm-platform/gpt-6-luna:low` | `/memory` generates explicit notes in `model-roles.memory.json` |
| widget | `llm-platform/gpt-6-luna:low` | `/widget` generates an on-demand status line |
| tiny | `llm-platform/gpt-6-luna:off` | Automatic session title (unless child/already named) |
| task | `llm-platform/gpt-6.1-sol:high` | Default for exported task definitions |
| advisor | `llm-platform/claude-sonnet-5-5:xhigh` | `/advisor` independent on-demand review |
| vision | `null` | Image-bearing requests inherit default; non-image-capable targets fail visibly |

Cleared roles inherit: smol/slow/task/vision → default; plan/advisor → slow; commit/tiny/widget → smol; memory → tiny. Cleared custom roles inherit default. A null default uses the first available physical model at runtime; immutable task frontmatter instead requires an exact resolvable default selector.

Compaction and other generic `direct` calls stay on the previous physical model and effort. Set `compactionRole = "smol"` to opt in to a separate role. Continuations retain the successful physical dispatch. Physical `/model` selection intentionally **bypasses** the virtual router; `/build`, `/plan`, `/slow`, `/use-role` restore `roles/auto`.

## Commands and editing

- `/models`: chat-consumer/custom-role screen, all-model/provider counts; Up/Down selects, Enter assigns model then thinking, `f` adds an explicit retry fallback and enables it, `d` clears assignment, `+ New role…` creates a usable custom conversation role, Escape closes. No inert judge/speech tabs.
- `/role research provider/model:high`, `/role research @slow`, `/role research -`: assign/alias/clear persistently.
- `/use-role research`: select any role for subsequent conversation turns.
- `/plan [prompt]`, `/slow [prompt]`, `/build [prompt]`: choose mode, optionally submit a prompt.
- Ctrl+Shift+U cycles `cycleOrder` (default smol/default/slow). Native Ctrl+P remains native model cycling; terminal support for the shifted shortcut varies.
- `/commit`, `/advisor`, `/memory`, `/widget` consume their actual model using explicit input or the last 24,000 characters of session transcript. This sends that bounded context to the configured role provider.
- `/role-agents` exports to the **separate** `model-roles-agents/` directory. It never rewrites Home Manager's `agents/*.md` files or follows their symlinks. Managed task changes require Nix regeneration; exports are not silently activated.

Selectors are exact `provider/model[:thinking]`, comma-separated availability alternatives, and recursive `@role[:thinking]` aliases. Thinking accepts off/minimal/low/medium/high/xhigh/max/inherit; `:auto` is rejected. The referring suffix wins over an alias target. Comma alternatives choose availability, not retry policy. Unavailable explicit assignments and alias cycles fail rather than silently substituting a provider. Pi clamps effort to physical-model capabilities.

`--smol`, `--slow`, `--plan` take a selector, not a boolean. `PI_<ROLE>_MODEL` overrides any declared role (hyphens become underscores). Flags/environment are process-only. `--roles-config` or `PI_MODEL_ROLES_CONFIG` supplies extra immutable JSON defaults (inline JSON or a path); generated Nix options remain the base.

Persistent changes overlay defaults in `<agent-dir>/model-roles.user.json`, written via same-directory atomic rename with mode 0600. Do not manage this file with Home Manager. Objects merge, explicit null clears an assignment, and fallback arrays replace their declared chain (including `[]`). Malformed overlay content is ignored with one warning per extension lifetime; immutable defaults remain intact. Simultaneous processes have **no merge/locking protocol**: last writer wins. Read-only/failed writes report errors instead of rewriting managed settings.

## Declarative configuration

Roles are on by default when `local.pi.llmPlatform.enable` is set, because the built-in role
selectors name LLM Platform models; `local.pi.routing.enable` follows `modelRoles.enable`.
Set `enable = false` to opt out, or set the role selectors to your own models.

```nix
local.pi.modelRoles = {
  enable = true;
  roles.vision = "llm-platform/your-image-model:high";
  # Soft planning is the default. This opt-in applies an exact tool ceiling:
  planMode.readOnly = true;
  # planMode.tools = [ "read" "grep" "question" "ast_grep_run" "fetch_content" ];
  # Empty/off by default. Enabling can disclose context to another provider:
  modelFallback = true;
  fallbackChains.default = [ "other-provider/model:low" ];
  cooldownMs = 60000;
};
local.pi.routing.enable = true;
```

Fallback precedence: exact provider/model, provider/*, active role, default; `[]` stops inheritance. A provider/* entry preserves the failed model ID. Bare fallback selectors inherit failed effort. Rate limits/429, overload, quota, context overflow and supported 5xx failures can fall back; authentication/authorization errors never do, even when their text also mentions quota/rate limits. Visited models prevent ping-pong. Successful fallback is used until fixed cooldown expiry, then primary is restored. Fallbacks are empty and disabled unless configured.

`modelRoles.taskAgents` maps build → `@default`, plan → `@plan`, scout → sol:low, explore → luna:low, title → `@tiny`. Nix resolves aliases and suffixes to `model:`/`thinking:` frontmatter. Because evaluation has no authenticated runtime catalog, **the first comma alternative** is rendered for a task agent; use exact available selectors there. Existing read-only scout/explore ceilings, required child extensions, MCP policy and context/skill inheritance remain unchanged. The task `plan` agent retains existing write/bash delegation tools; primary plan read-only is an independent opt-in.

## Planning instructions

`local.pi.modelRoles.planMode.instructions` is a multiline string appended to the
system prompt only while the primary conversation is in `/plan` mode. It defaults
to `""`, retaining the original short planning reminder. `/build` stops injecting
it; session reload restores it when the saved mode is `plan`. It does not alter
models, tool permissions, or the separately managed `plan` task agent.

Framework sets this option in `users/adriel-cachyos/default.nix` with
`builtins.readFile ../../dotfiles/pi/planning-instructions.md`. Edit that prompt
file, or replace the option with inline text in Nix:

```nix
local.pi.modelRoles.planMode.instructions = ''
  Ground every claim in inspected code. Resolve implementation decisions and
  include concrete behavioral verification before requesting plan approval.
'';
```

The managed prompt adapts OMP 18.12.6's
[`plan-mode-active.md`](https://github.com/can1357/oh-my-pi/blob/45c35e40c46166dc726ccc52f5d27f40f2449f99/packages/coding-agent/src/prompts/system/plan-mode-active.md):
repository-grounded discovery, decision-complete steps, explicit interfaces,
behavioral verification, contingencies, and a completeness check. Pi uses the
existing Superpowers workflow, repository-approved planning paths, the blocking
`question` tool, and an explicit `/build` handoff, not OMP's `local://` or
`xd://propose` protocol. This is prompt guidance, not OMP's permission engine;
`planMode.readOnly` remains a separate opt-in and custom text cannot expand its
tool ceiling. The runtime read-only reminder is retained even with custom text.

## Honest omp parity boundary

Not reproduced: background advisor watchdog/steering; automatic memory consolidation/retrieval; background-job widget engine; judge/classifier-driven auto-thinking; image/web/speech/dictation model-kind runners/tabs; path-scoped enabledModels; omp presets/fuzzy priority catalogs; account/credential round-robin and usage-aware routing; Retry-After/quota-reset parsing, fallbackOn variants, never-revert policy or context promotion. Arbitrary extensions choosing physical models cannot be intercepted. Task overlay edits do not live-rewrite immutable frontmatter. Command-mode restoration follows session start, not arbitrary `/tree` branch navigation. The role screen is intentionally a smaller real-consumer UI, not a claim of every omp feature.

The check exercises real Pi with three loopback-only models, request logs, 120/80-column screens, overlay edit and two reloads, CLI override, default/plan/build routing, 429 fallback/cooldown restoration, image routing, and headless JSON output. Unit tests cover deterministic resolution and command/persistence policy. No real credentials, model endpoints, activation or runtime downloads are involved.
