export type Thinking = "off" | "minimal" | "low" | "medium" | "high" | "xhigh" | "max";
export type Physical = { provider: string; id: string; input?: string[]; reasoning?: boolean };
export type Route = { model: Physical; thinkingLevel: Thinking };
export type Config = {
  modelRoles?: Record<string, string | null>;
  retry?: { modelFallback?: boolean; cooldownMs?: number; fallbackChains?: Record<string, string[]> };
  cycleOrder?: string[];
  task?: { agentModelOverrides?: Record<string, string> };
  agents?: Record<string, { description: string; prompt: string; tools?: string[] }>;
  autoTitle?: boolean;
  autoTitleRefreshPercent?: number | null;
  compactionRole?: string | null;
  planMode?: { readOnly?: boolean; tools?: string[]; instructions?: string };
};
export const builtins = ["default", "smol", "slow", "vision", "plan", "commit", "tiny", "memory", "task", "advisor", "widget"];
const levels: Record<string, true> = { off: true, minimal: true, low: true, medium: true, high: true, xhigh: true, max: true, inherit: true };
const inherits: Record<string, string> = { smol: "default", slow: "default", plan: "slow", commit: "smol", tiny: "smol", memory: "tiny", task: "default", advisor: "slow", widget: "smol", vision: "default" };
export function mergeConfig(base: Config, overlay: Config): Config {
  return { ...base, ...overlay, modelRoles: { ...base.modelRoles, ...overlay.modelRoles },
    retry: { ...base.retry, ...overlay.retry, fallbackChains: { ...base.retry?.fallbackChains, ...overlay.retry?.fallbackChains } },
    planMode: { ...base.planMode, ...overlay.planMode },
    task: { ...base.task, ...overlay.task, agentModelOverrides: { ...base.task?.agentModelOverrides, ...overlay.task?.agentModelOverrides } } };
}
export function parseSelector(value: string): { reference: string; thinking?: Thinking | "inherit" } {
  const text = value.trim();
  const colon = text.lastIndexOf(":");
  const suffix = colon < 0 ? undefined : text.slice(colon + 1);
  if (colon >= 0 && !Object.hasOwn(levels, suffix!)) throw new Error(`Unsupported thinking suffix: ${suffix}`);
  const reference = colon < 0 ? text : text.slice(0, colon);
  if (!/^(?:@[a-z][\w-]*|[^\s/:,]+\/[^\s,:]+)$/.test(reference)) throw new Error(`Expected provider/model or @role: ${value}`);
  return { reference, thinking: suffix as Thinking | "inherit" | undefined };
}
export function roleNames(config: Config): string[] {
  return [...new Set([...builtins, ...Object.keys(config.modelRoles ?? {})])];
}
export function resolveSelector(value: string, config: Config, models: Physical[], thinking: Thinking = "off", seen: string[] = []): Route {
  let lastError: unknown;
  for (const candidate of value.split(",")) {
    try {
      const { reference, thinking: requested } = parseSelector(candidate);
      let route: Route;
      if (reference.startsWith("@")) route = resolveRole(reference.slice(1), config, models, thinking, seen);
      else {
        const slash = reference.indexOf("/");
        const model = models.find(m => m.provider === reference.slice(0, slash) && m.id === reference.slice(slash + 1));
        if (!model) throw new Error(`Unavailable model: ${reference}`);
        route = { model, thinkingLevel: thinking };
      }
      return { model: route.model, thinkingLevel: requested && requested !== "inherit" ? requested : route.thinkingLevel };
    } catch (error) { lastError = error; }
  }
  throw lastError ?? new Error(`Empty selector: ${value}`);
}
export function resolveRole(role: string, config: Config, models: Physical[], thinking: Thinking = "off", seen: string[] = []): Route {
  if (!/^[a-z][\w-]*$/.test(role)) throw new Error(`Invalid role: ${role}`);
  if (seen.includes(role)) throw new Error(`Role alias cycle: ${[...seen, role].join(" -> ")}`);
  const selector = config.modelRoles?.[role];
  const nextSeen = [...seen, role];
  if (selector) return resolveSelector(selector, config, models, thinking, nextSeen);
  if (role !== "default") return resolveRole(inherits[role] ?? "default", config, models, thinking, nextSeen);
  const model = models[0];
  if (!model) throw new Error("No available physical models");
  return { model, thinkingLevel: thinking };
}
export const modelKey = (model: Physical) => `${model.provider}/${model.id}`;
export function fallbackSelectors(config: Config, role: string, model: Physical): string[] {
  const chains = config.retry?.fallbackChains ?? {};
  return chains[modelKey(model)] ?? chains[`${model.provider}/*`] ?? chains[role] ?? chains.default ?? [];
}
export function fallbackRoutes(config: Config, role: string, failed: Route, models: Physical[]): Route[] {
  const routes: Route[] = [];
  for (const selector of fallbackSelectors(config, role, failed.model)) {
    const expanded = selector.replace(/^([^/]+)\/\*(?=:|$)/, `$1/${failed.model.id}`);
    try { routes.push(resolveSelector(expanded, config, models, failed.thinkingLevel)); } catch { /* Skip unavailable candidates in the declared chain. */ }
  }
  return routes;
}
export const retryable = (error: string) => !/\b40[13]\b|unauthori[sz]ed|authori[sz]ation|authenticat|api.?key|credential|invalid.{0,12}token|permission.?denied|access.?denied|forbidden/i.test(error)
  && /429|overload|rate.?limit|quota|resource.exhausted|context.{0,25}(?:length|overflow|exceed)|(?:too many|maximum).{0,15}tokens|50[0234]|529/i.test(error);
export type RouterState = { role: string; cooldowns: Record<string, number>; visited: string[] };
export type Request = {
  reason: "user" | "continuation" | "retry" | "direct";
  thinkingLevel?: Thinking;
  previous?: { model: Physical; thinkingLevel?: Thinking };
  failed?: { model: Physical; thinkingLevel?: Thinking; message?: { errorMessage?: string } };
  state?: RouterState;
  messages?: readonly { role: string; content: string | readonly { type: string; text?: string }[] }[];
};
export function chooseRoute(config: Config, request: Request, models: Physical[], mode = "default", forced?: string, now = Date.now()): Route & { state?: RouterState; role: string } {
  const old: RouterState = request.state ?? { role: mode, cooldowns: {}, visited: [] };
  const cooldowns = Object.fromEntries(Object.entries(old.cooldowns ?? {}).filter(([, until]) => until > now));
  const thinking = request.thinkingLevel ?? "off";
  const sticky = request.reason === "continuation" || (request.reason === "direct" && !forced && !config.compactionRole);
  if (sticky && request.previous) return { model: request.previous.model, thinkingLevel: request.previous.thinkingLevel ?? thinking, role: old.role, state: old };
  const lastUser = [...(request.messages ?? [])].reverse().find(m => m.role === "user");
  const text = typeof lastUser?.content === "string" ? lastUser.content : (lastUser?.content ?? []).filter(p => p.type === "text").map(p => p.text).join("\n");
  const images = (request.messages ?? []).some(m => Array.isArray(m.content) && m.content.some(p => p.type === "image"));
  const role = forced ?? (request.reason === "retry" ? old.role : request.reason === "direct" ? config.compactionRole ?? mode : images ? "vision" : /\bultrathink\b/i.test(text) ? "slow" : mode);
  const primary = resolveRole(role, config, models, thinking);
  let route = primary;
  const visited = request.reason === "retry" ? [...(old.visited ?? [])] : [];
  if (request.reason === "retry" && request.failed) {
    if (!config.retry?.modelFallback || !retryable(request.failed.message?.errorMessage ?? "")) return { model: request.failed.model, thinkingLevel: request.failed.thinkingLevel ?? thinking, role, state: old };
    const key = modelKey(request.failed.model);
    cooldowns[key] = now + (config.retry.cooldownMs ?? 60000);
    visited.push(key);
    const next = fallbackRoutes(config, role, { model: request.failed.model, thinkingLevel: request.failed.thinkingLevel ?? thinking }, models).find(r => !visited.includes(modelKey(r.model)) && !cooldowns[modelKey(r.model)]);
    if (!next) throw new Error(`Fallback chain exhausted for ${role}: ${visited.join(", ")}`);
    route = next;
  } else if (cooldowns[modelKey(primary.model)] && config.retry?.modelFallback) {
    const next = fallbackRoutes(config, role, primary, models).find(r => !cooldowns[modelKey(r.model)]);
    if (!next) throw new Error(`No healthy configured route for ${role}`);
    route = next;
  }
  if (images && request.reason !== "direct" && !route.model.input?.includes("image")) throw new Error(`Role ${role} must resolve to an image-capable model`);
  return { ...route, role, state: { role, cooldowns, visited } };
}
export function agentFrontmatter(config: Config, name: string, models: Physical[]): string {
  const definition = config.agents?.[name];
  if (!definition) throw new Error(`No agent definition for ${name}`);
  const route = resolveSelector(config.task?.agentModelOverrides?.[name] ?? "@task", config, models);
  return `---\nname: ${JSON.stringify(name)}\ndescription: ${JSON.stringify(definition.description)}\nmodel: ${JSON.stringify(modelKey(route.model))}\nthinking: ${route.thinkingLevel}\n${definition.tools ? `tools: ${definition.tools.join(", ")}\n` : ""}---\n${definition.prompt}\n`;
}
