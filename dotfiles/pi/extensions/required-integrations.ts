import { accessSync, constants } from "node:fs";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export function requireIntegrations(pi: ExtensionAPI, register, extensions: Array<{ id: string; path: string }>) {
  let registration, valid = false, failure = "Required child integrations did not initialize";
  pi.on("session_start", (_event, ctx) => {
    valid = false; registration?.dispose(); registration = undefined;
    try {
      for (const extension of extensions) accessSync(extension.path, constants.R_OK);
      registration = register({ sessionId: ctx.sessionManager.getSessionId(), requireForAllRunners: true, extensions });
      valid = true;
    } catch (error) { failure = error instanceof Error ? error.message : String(error); throw error; }
  });
  pi.on("tool_call", event => {
    if (event.toolName === "subagent" && !valid) return { block: true, reason: failure };
  });
  pi.on("session_shutdown", () => { valid = false; registration?.dispose(); registration = undefined; });
}
