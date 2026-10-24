# OMP runtime MCP compatibility bridge

The Reddit integration uses a source patch composed with official OMP 18.12.6 by
`packages/omp-path-reddit-mcp-api.nix`. It adds native extension methods; it does
not install a second MCP/OAuth stack or modify live configuration.

Call after session initialization:

```ts
await pi.registerMcpServer(name, nativeConfig, policy);
const servers = pi.getMcpServers();
await pi.unregisterMcpServer(name);
```

The loader binds ownership to the actual extension instance and session runtime.
Children can inspect redacted snapshots, but cannot mutate registrations. Literal
and normalized-name collisions are refused. Reload keeps the runtime layer; stale
cleanup does not remove a replacement owner or hide a project-defined server.
Disabled explicit declarations and native disable lists also reserve their
normalized namespace. Late discovery must retire the matching runtime transport,
not relabel its connection: retained handles keep their old, revoked guard.

`policy({serverName,toolName,cwd})` returns `{allow,reason?}`, optionally async.
It runs before outbound argument materialization and before MCP calls/retries,
including device dispatch. An optional synchronous `policy.isVisible(name,cwd)`
filters definitions without running the execution predicate merely to list tools.
Execution always rechecks; hiding is not the authorization boundary.

Snapshots contain source, redacted URL, connection/error state, non-secret auth
state (`stored` is not a claim that access works), and native/original tool names.
Never serialize runtime provider configurations or project tickets into Nix
declarations, logs or shared files.

Runtime-owned OAuth uses OMP's existing vault, PKCE, cancellation and refresh.
Native `/mcp reauth <name>` and `/mcp unauth <name>` operate on credentials only;
enable/disable/remove must go through the owner and cannot create file overrides.
For owned entries, `oauth.scope` is authoritative over discovery and embedded URL
scopes, including DCR. `oauth.expectedIssuer` and `oauth.expectedResource` pin the
discovered metadata before browser/client/token actions. Tool challenges do not
automatically launch browser authentication for owned entries.

The controller's protected-resource metadata fetch is bounded (1 MiB, deadline,
same origin, no redirects). Native `/mcp reauth` performs its own OAuth discovery:
that inherited upstream fetch can follow redirects and has no body-size cap.
Issuer/resource pins are checked before browser/DCR/token actions, not before
every discovery request. Do not describe all OAuth discovery as bounded; scoped
native metadata hardening remains deferred in TODO.md.

Verification checks: `omp-mcp`, `omp-mcp-xdev`, `omp-mcp-lifecycle`,
`omp-mcp-auth`, `omp-mcp-auth-invalid`, and the existing `omp-wire`. All execute
the compiled binary with synthetic services; the auth check uses a fake browser,
native loopback callback/vault and immutable-config canaries. No live credentials,
browser authorization or paid model calls establish these results.
`omp-mcp-reserved` adds compiled disabled-definition/list canaries;
`omp-mcp-ownership` exercises the real native manager with deterministically delayed
discovery and live project reconciliation in its package build environment.

The patch-removal criteria and upstream evidence are recorded in TODO.md.
See [the Reddit hub](omp.md#reddit-hub) for the completed command/controller.
