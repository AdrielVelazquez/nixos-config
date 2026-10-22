import { readFileSync, renameSync, unlinkSync, writeFileSync } from "node:fs";
import { createHash, randomUUID } from "node:crypto";
import { join, resolve, sep } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

function started(pid: number): string {
  return readFileSync(`/proc/${pid}/stat`, "utf8").split(")").slice(1).join(")").trim().split(/\s+/)[19];
}
function state() {
  const root = process.env.HEADROOM_PI_STATE_DIR;
  if (!root || !process.env.HEADROOM_PI_INSTANCE) throw new Error("Start Pi through the managed Headroom launcher");
  const info = JSON.parse(readFileSync(join(root, "state.json"), "utf8"));
  if (!info.ready || info.stopping || info.instance !== process.env.HEADROOM_PI_INSTANCE ||
      started(info.managerPid) !== info.managerStarted ||
      process.env.HEADROOM_PROXY_URL !== `http://127.0.0.1:${info.port}`) throw new Error("The owned Headroom proxy is unavailable; restart this Pi session");
  return { root, info };
}
function lease(root: string, id: string, value: unknown) {
  const file = join(root, "leases", `${id}.json`), temp = join(root, "leases", `.tmp-${randomUUID()}`);
  writeFileSync(temp, JSON.stringify(value), { flag: "wx", mode: 0o600 });
  renameSync(temp, file);
  return file;
}

/** Optional routing integrations pin admitted async runs before their child starts. */
export function reserveHeadroomRun(asyncDirectory: string): void {
  if (!process.env.HEADROOM_PI_STATE_DIR) return;
  const { root, info } = state();
  const allowed = process.env.PI_SUBAGENTS_TEMP_ROOT;
  const directory = resolve(asyncDirectory);
  if (!allowed || !directory.startsWith(resolve(allowed) + sep)) throw new Error("Async run is outside the managed Pi runtime root");
  const hex = createHash("sha256").update(directory).digest("hex").slice(0, 32);
  const id = `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  lease(root, id, { instance: info.instance, kind: "run", statePath: join(directory, "status.json"), deadline: Date.now() + 60_000 });
}

export default function (pi: ExtensionAPI) {
  let file: string | undefined, valid = false, failure = "Headroom is required for this Pi configuration";
  let stopAdmissions: (() => void) | undefined;
  let project: string | undefined;
  let config: { gitCommand?: string; user?: string; adapters?: Array<{ upstreamOrigins: string[]; urlEnv: string; requiredEnv: string }> } = {};
  pi.on("session_start", async (_event, ctx) => {
    stopAdmissions?.(); stopAdmissions = undefined;
    try {
      const owned = state();
      config = JSON.parse(readFileSync(process.env.HEADROOM_PI_CONFIG!, "utf8"));
      const result = await pi.exec(config.gitCommand ?? "git", ["-C", ctx.cwd, "rev-parse", "--show-toplevel"]);
      project = resolve(result.code === 0 ? result.stdout.trim() : ctx.cwd);
      if (project !== owned.info.project) throw new Error("Start a separate managed Pi session for a different repository");
      file = lease(owned.root, randomUUID(), { instance: owned.info.instance, kind: "process", pid: process.pid, started: started(process.pid) });
      valid = true;
      // The package emits admission for tools, slash commands, RPC and event-bus
      // launches before returning to the parent. A tool_result misses most paths
      // and cannot hold a workflow's proxy between native child sessions.
      stopAdmissions = pi.events.on("subagent:async-started", event => {
        const admitted = event as { asyncDir?: unknown };
        if (typeof admitted?.asyncDir === "string") reserveHeadroomRun(admitted.asyncDir);
      });
    } catch (error) { valid = false; failure = error instanceof Error ? error.message : String(error); throw error; }
  });
  pi.on("input", (_event, ctx) => {
    if (!valid) { ctx.ui.notify(failure, "error"); return { action: "handled" }; }
  });
  pi.on("before_provider_headers", event => {
    // This event has headers only. Scope attribution to the provider's actual
    // managed-proxy routing header, not the session model (titles may differ).
    const origin = Object.entries(event.headers).find(([key]) => key.toLowerCase() === "x-headroom-base-url")?.[1];
    if (valid && project && config.adapters?.some(adapter => adapter.upstreamOrigins?.includes(origin as string) &&
        process.env[adapter.urlEnv] === process.env.HEADROOM_PROXY_URL && process.env[adapter.requiredEnv] === "1")) {
      event.headers["x-headroom-cwd"] = project;
      if (config.user) event.headers["x-headroom-user-id"] = config.user;
    }
  });
  pi.on("session_shutdown", () => { valid = false; stopAdmissions?.(); stopAdmissions = undefined;
    if (file) { try { unlinkSync(file); } catch {} file = undefined; } });
}
