import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export const UNAVAILABLE_BASE_URL = "http://127.0.0.1:1/headroom-required";

export type ProviderRouting = { routes: Record<string, string>; urlEnv: string; requiredEnv: string };

/**
 * Re-points built-in Pi providers at the Headroom proxy this session owns. Without the launcher's
 * contract the providers get an address nothing listens on: a missing proxy is an error, never
 * direct inference.
 */
export function routeProvidersThroughHeadroom(
  pi: Pick<ExtensionAPI, "registerProvider" | "on">,
  routing: ProviderRouting,
  env: NodeJS.ProcessEnv = process.env,
): void {
  const proxy = env[routing.urlEnv];
  const owned = proxy !== undefined && proxy === env.HEADROOM_PROXY_URL && /^http:\/\/127\.0\.0\.1:\d+$/.test(proxy)
    && env[routing.requiredEnv] === "1";
  if (owned) {
    for (const [id, upstream] of Object.entries(routing.routes)) {
      // Headroom appends `/v1/chat/completions` (or `/v1/responses`) to this base itself.
      const base = upstream.replace(/\/v1\/?$/, "");
      pi.registerProvider(id, { baseUrl: `${proxy}/v1`, headers: { "x-headroom-base-url": base } });
    }
    return;
  }
  for (const id of Object.keys(routing.routes)) pi.registerProvider(id, { baseUrl: UNAVAILABLE_BASE_URL });
  pi.on("session_start", (_event, ctx) => {
    ctx.ui.notify("Start Pi through the managed Headroom launcher; provider inference is disabled", "error");
  });
}
