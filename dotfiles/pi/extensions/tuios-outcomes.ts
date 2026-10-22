import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

/** Correct upstream v2's unconditional done report, without modifying its asset. */
export function createTuiosOutcomes(pi: ExtensionAPI, tuios: string) {
  const pane = process.env.TUIOS_PANE_ID;
  const child = process.env.PI_SUBAGENT_CHILD === "1";
  let tui = false, outcome: string | undefined, generation = 0;
  pi.on("session_start", (_event, ctx) => { tui = ctx.mode === "tui" && !child && !!pane; generation++; outcome = undefined; });
  pi.on("session_shutdown", () => { generation++; tui = false; });
  pi.on("agent_start", () => { generation++; outcome = undefined; });
  pi.on("message_end", event => {
    if (event.message.role === "assistant") outcome = event.message.stopReason;
  });
  pi.on("agent_settled", async (event, ctx) => {
    if (!tui || !ctx.isIdle() || (!event.aborted && !["error", "aborted"].includes(outcome ?? ""))) return;
    const turn = generation, session = ctx.sessionManager.getSessionId();
    const message = event.aborted || outcome === "aborted" ? "Interrupted" : "Provider request failed";
    // The upstream asset spawns its report without awaiting it. Retry only the
    // conditional correction; never overwrite a new turn, prompt or session.
    for (let attempt = 0; attempt < 20 && generation === turn && ctx.isIdle() && ctx.sessionManager.getSessionId() === session; attempt++) {
      try {
        const result = await pi.exec(tuios, ["set-agent-state", "errored", "--if-state", "done", "--window", pane!,
          "--harness", "pi", "--agent-session-id", session, "--source", "hook", "--message", message], { timeout: 2000 });
        if (result.code !== 0 || !result.stderr.trim() || /foreign|session|harness/i.test(result.stderr)) return;
      } catch { return; }
      await new Promise(resolve => setTimeout(resolve, 25));
    }
  });
}
