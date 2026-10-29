import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export function routeCodexThroughHeadroom(
  pi: Pick<ExtensionAPI, "registerProvider" | "on">,
  routing: { urlEnv: string; requiredEnv: string },
  env: NodeJS.ProcessEnv = process.env,
): void {
  const proxy = env[routing.urlEnv];
  const owned = proxy !== undefined && proxy === env.HEADROOM_PROXY_URL && /^http:\/\/127\.0\.0\.1:\d+$/.test(proxy)
    && env[routing.requiredEnv] === "1";
  if (owned) {
    pi.registerProvider("openai-codex", {
      baseUrl: `${proxy}/v1`,
      headers: { "x-headroom-base-url": "https://chatgpt.com", "x-client": "codex" },
    });
    return;
  }
  pi.registerProvider("openai-codex", { baseUrl: "http://127.0.0.1:1/headroom-required" });
  pi.on("session_start", (_event, ctx) => {
    ctx.ui.notify("Start Pi through the managed Headroom launcher; Codex inference is disabled", "error");
  });
}
