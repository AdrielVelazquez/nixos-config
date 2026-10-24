import type { ExtensionAPI, ProviderConfig } from "@earendil-works/pi-coding-agent";

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
    const headers = (upstream: string) => ({ "x-headroom-base-url": upstream.replace(/\/v1\/?$/, "") });
    for (const [id, upstream] of Object.entries(routing.routes)) {
      // Headroom appends `/v1/chat/completions` (or `/v1/responses`) to this base itself, and Google's
      // `/models/<id>:streamGenerateContent` path follows the base unchanged.
      pi.registerProvider(id, { baseUrl: `${proxy}/v1`, headers: headers(upstream) });
    }
    // The Anthropic client appends `/v1/messages` to its base, so a model on that protocol needs the bare proxy:
    // with `/v1` it is requested at `/v1/v1/messages`, which the gateway answers with an empty-body 404. A
    // provider's base applies to all its models, so such a provider is registered again with each model's own.
    pi.on("session_start", (_event, ctx) => {
      for (const [id, upstream] of Object.entries(routing.routes)) {
        const models = ctx.modelRegistry.getModelsOfType("chat", id);
        if (!models.some(model => model.api === "anthropic-messages")) continue;
        pi.registerProvider(id, {
          baseUrl: `${proxy}/v1`,
          headers: headers(upstream),
          models: models.map(model => (model.api === "anthropic-messages" ? { ...model, baseUrl: proxy } : model)) as ProviderConfig["models"],
        });
      }
    });
    return;
  }
  for (const id of Object.keys(routing.routes)) pi.registerProvider(id, { baseUrl: UNAVAILABLE_BASE_URL });
  pi.on("session_start", (_event, ctx) => {
    ctx.ui.notify("Start Pi through the managed Headroom launcher; provider inference is disabled", "error");
  });
}
