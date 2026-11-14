// Reads the OpenCode Go API key at request time and contributes the monthly quota to the visual owner's
// footer. It never owns the footer and never logs or places the key in a status.
import { readFile } from "node:fs/promises";
import { formatUsage, monthlyUsage } from "./opencode-go-usage-core.ts";

const STATUS = "opencode-go-usage";
const DEFAULT_URL = "https://opencode.ai/zen/go/v1/usage";
const DEFAULT_REFRESH_MS = 60_000;
const DEFAULT_TIMEOUT_MS = 5_000;

export function createOpenCodeGoUsage(pi, options) {
  const url = options.url ?? DEFAULT_URL;
  const refreshMs = options.minRefreshMs ?? DEFAULT_REFRESH_MS;
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  let lastRefresh = 0;
  let inFlight = false;

  const refresh = async (_event, ctx, force = false) => {
    const now = Date.now();
    if (inFlight || (!force && now - lastRefresh < refreshMs)) return;
    inFlight = true;
    lastRefresh = now;
    try {
      const key = (await readFile(options.keyFile, "utf8")).trim();
      if (!key) {
        ctx.ui.setStatus(STATUS, "Go —");
        return;
      }
      const response = await fetch(url, {
        headers: { Authorization: `Bearer ${key}`, Accept: "application/json" },
        signal: AbortSignal.timeout(timeoutMs),
      });
      if (!response.ok) {
        ctx.ui.setStatus(STATUS, "Go —");
        return;
      }
      const usage = monthlyUsage(await response.json());
      ctx.ui.setStatus(STATUS, usage ? formatUsage(usage, Date.now()) : "Go —");
    } catch {
      ctx.ui.setStatus(STATUS, "Go —");
    } finally {
      inFlight = false;
    }
  };

  pi.on("session_start", (event, ctx) => refresh(event, ctx, true));
  pi.on("agent_end", (event, ctx) => refresh(event, ctx));
  pi.on("session_shutdown", (_event, ctx) => ctx.ui.setStatus(STATUS, undefined));
}
