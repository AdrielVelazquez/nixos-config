const THROTTLED_FLOOR_MS = 5_000;
const THROTTLED_DEFAULT_MS = 60_000;
const THROTTLED_CAP_MS = 300_000;
const REFUSED_MS = 600_000;
export const EXA_API_HOST = "api.exa.ai";

export interface CooldownOptions {
  hosts: readonly string[];
  now?: () => number;
}

const hostOf = (input: Parameters<typeof fetch>[0]): string => {
  try { return new URL(typeof input === "string" || input instanceof URL ? input : input.url).hostname; }
  catch { return ""; }
};

const retryAfterMs = (response: Response): number => {
  const seconds = Number(response.headers.get("retry-after"));
  const ms = Number.isFinite(seconds) && seconds > 0 ? seconds * 1000 : THROTTLED_DEFAULT_MS;
  return Math.min(Math.max(ms, THROTTLED_FLOOR_MS), THROTTLED_CAP_MS);
};

// A provider that answered 429, 402 (credits spent), 401 or 403 (key revoked, bot challenge) is not asked again until
// it has cooled down: the request is answered locally with a 429, the status the search failover already treats as
// quota, so the next provider is tried without spending a round trip on the one known to refuse. A 401 or 403 is
// answered that way at once, because upstream would otherwise end the search on an authentication error.
export function createProviderCooldown({ hosts, now = Date.now }: CooldownOptions) {
  const providers = new Set(hosts);
  const coolingUntil = new Map<string, { until: number; status: number }>();
  const isCooling = (host: string) => (coolingUntil.get(host)?.until ?? 0) > now();
  const wrap = (inner: typeof fetch): typeof fetch => async (input, init) => {
    const host = hostOf(input);
    if (!providers.has(host)) return inner(input, init);
    const cooling = coolingUntil.get(host);
    if (cooling && isCooling(host)) {
      const seconds = Math.ceil((cooling.until - now()) / 1000);
      return new Response(`${host} is cooling down for ${seconds}s after HTTP ${cooling.status}; request skipped`, {
        status: 429,
        headers: { "retry-after": String(seconds) },
      });
    }
    const response = await inner(input, init);
    if (response.status === 429) coolingUntil.set(host, { until: now() + retryAfterMs(response), status: 429 });
    else if (response.status === 402) coolingUntil.set(host, { until: now() + REFUSED_MS, status: 402 });
    else if (response.status === 401 || response.status === 403) {
      coolingUntil.set(host, { until: now() + REFUSED_MS, status: response.status });
      // The provider's own body is dropped: it may echo the credential that was rejected.
      return new Response(`${host} refused the request (HTTP ${response.status}) and is skipped for ${REFUSED_MS / 1000}s`, {
        status: 429,
        headers: { "retry-after": String(REFUSED_MS / 1000) },
      });
    }
    return response;
  };
  return { wrap, isCooling };
}

export const withProviderCooldown = (inner: typeof fetch, options: CooldownOptions): typeof fetch =>
  createProviderCooldown(options).wrap(inner);

export interface ExaKeyOptions {
  env: Record<string, string | undefined>;
  readKey: () => string | null;
  isCooling: () => boolean;
}

// pi-web-access asks Exa's paid API when a key is configured and its keyless MCP when none is. The key is put in
// the environment only while a search runs, and left out while the API is cooling down (credit spent or throttled)
// or the key cannot be read, so Exa itself falls back to the keyless MCP before the next provider is tried.
export function createExaKeyScope({ env, readKey, isCooling }: ExaKeyOptions) {
  let active = 0;
  let before: string | undefined;
  return async <T>(run: () => Promise<T>): Promise<T> => {
    if (active++ === 0) before = env.EXA_API_KEY;
    let key: string | null = null;
    if (!isCooling()) { try { key = readKey(); } catch { key = null; } }
    if (key) env.EXA_API_KEY = key; else delete env.EXA_API_KEY;
    try { return await run(); }
    finally {
      if (--active === 0) { if (before === undefined) delete env.EXA_API_KEY; else env.EXA_API_KEY = before; }
    }
  };
}
