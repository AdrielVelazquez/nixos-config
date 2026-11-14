// OpenCode Go publishes only the three quota windows' percentages and reset times, not dollar amounts.
// The footer shows the monthly window because that is the subscription's whole allowance.
export interface MonthlyUsage {
  percent: number;
  resetsAt: number | null;
}

function record(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function percent(value: unknown): number | undefined {
  if (typeof value !== "number" || !Number.isFinite(value)) return undefined;
  return Math.max(0, Math.min(100, Math.round(value)));
}

function time(value: unknown): number | null {
  if (typeof value !== "string") return null;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : null;
}

export function monthlyUsage(payload: unknown): MonthlyUsage | undefined {
  if (!record(payload) || !record(payload.usage) || !record(payload.usage.monthly)) return undefined;
  const monthly = payload.usage.monthly;
  const used = monthly.status === "rate-limited" ? 100 : percent(monthly.percent);
  if (used === undefined) return undefined;
  return { percent: used, resetsAt: time(monthly.resetsAt) };
}

function countdown(ms: number): string {
  const days = Math.floor(ms / 86_400_000);
  if (days >= 1) return `${days}d`;
  const hours = Math.floor(ms / 3_600_000);
  if (hours >= 1) return `${hours}h`;
  return `${Math.max(1, Math.floor(ms / 60_000))}m`;
}

export function formatUsage(usage: MonthlyUsage, now: number): string {
  const reset = usage.resetsAt !== null && usage.resetsAt > now ? ` ↻${countdown(usage.resetsAt - now)}` : "";
  return `Go ${usage.percent}%${reset}`;
}
