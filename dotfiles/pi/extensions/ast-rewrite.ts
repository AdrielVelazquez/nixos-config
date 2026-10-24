import { realpath } from "node:fs/promises";
import { isAbsolute, relative, resolve, sep } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { pinnedAstRunner, trackAstSpills } from "./ast-readonly.ts";

const REWRITE = "ast_grep_rewrite";

/** The package resolves a target as: leading "@" stripped, "" or "." is the session directory. */
function targetOf(cwd: string, path: string): string {
  const cleaned = path.trim();
  const stripped = cleaned.startsWith("@") ? cleaned.slice(1) : cleaned;
  if (stripped === "" || stripped === ".") return cwd;
  return isAbsolute(stripped) ? stripped : resolve(cwd, stripped);
}

async function physical(path: string): Promise<string> {
  try { return await realpath(path); } catch { return resolve(path); }
}

/**
 * Structural rewrites for the interactive (primary) session only. The package already previews by default,
 * requires a trusted project, a prior preview when headless and a confirmation dialog when interactive; this adds
 * the pinned runner and a project boundary. Native children never load this entry, so Code Mode in a read-only
 * child cannot reach the tool.
 */
export function installAstRewrite(pi: ExtensionAPI, createTools, binary: string, configFile: string) {
  const tool = createTools(pinnedAstRunner(pi, binary, configFile)).find(candidate => candidate.name === REWRITE);
  if (!tool) throw new Error(`Pinned AST package is missing ${REWRITE}`);
  const track = trackAstSpills(pi);
  pi.registerTool({ ...tool, async execute(...args) {
    const result = await tool.execute(...args);
    track(result);
    return result;
  } });
  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName !== REWRITE) return undefined;
    // The schema rejects the package's `file` alias (additionalProperties is false), so `path` is the only target.
    const requested = typeof event.input?.path === "string" ? event.input.path : ".";
    const rel = relative(await physical(ctx.cwd), await physical(targetOf(ctx.cwd, requested)));
    if (rel === ".." || rel.startsWith(`..${sep}`) || isAbsolute(rel)) {
      return { block: true, reason: `${REWRITE} only rewrites files inside the project; ${requested} is outside the project` };
    }
    return undefined;
  });
  pi.on("session_start", (_event, ctx) => ctx.ui.setStatus("ast-grep", "ast-grep RW"));
}
