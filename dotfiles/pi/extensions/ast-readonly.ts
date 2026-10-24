import { rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export const AST_READ_TOOLS = ["ast_grep_run", "ast_grep_scan", "ast_grep_outline", "ast_grep_debug_query", "ast_grep_languages"];

// With `--config` ast-grep 0.51 prints this one line on every run, successful or not (the cause is not established;
// a trusted-configs.json under XDG_CONFIG_HOME did not remove it). The package treats any stderr from a run with
// no matches as that run's error, so an empty search read as a failure. Real failures print other lines; kept.
const PINNED_CONFIG_NOISE = "ERROR: run: No such file or directory (os error 2)";

/** Run the pinned ast-grep, ignoring ambient AST_GREP_BIN and project sgconfig/custom native grammars. */
export function pinnedAstRunner(pi: ExtensionAPI, binary: string, configFile: string) {
  return async (_binary, args, options = {}) => {
    const result = await pi.exec(binary, ["--custom-languages", "ignore", "--config", configFile, ...args], {
      cwd: options.cwd, signal: options.signal, timeout: options.timeoutMs,
    });
    return { ...result, stderr: result.stderr.split("\n").filter(line => line.trim() !== PINNED_CONFIG_NOISE).join("\n") };
  };
}

/** Remember this session's full-output spill directories and remove only those at shutdown. */
export function trackAstSpills(pi: ExtensionAPI) {
  const spills = new Set<string>();
  pi.on("session_shutdown", async () => {
    await Promise.all([...spills].map(dir => rm(dir, { recursive: true, force: true })));
    spills.clear();
  });
  return result => {
    const file = result.details?.fullOutputPath;
    if (typeof file === "string" && dirname(dirname(file)) === tmpdir() && basename(dirname(file)).startsWith("pi-ast-grep-")) spills.add(dirname(file));
  };
}

export function installReadOnlyAst(pi: ExtensionAPI, createTools, binary: string, configFile: string) {
  const tools = createTools(pinnedAstRunner(pi, binary, configFile)), track = trackAstSpills(pi);
  for (const name of AST_READ_TOOLS) {
    const tool = tools.find(tool => tool.name === name);
    if (!tool) throw new Error(`Pinned AST package is missing ${name}`);
    const scan = name === "ast_grep_scan";
    const properties = scan ? Object.fromEntries(Object.entries(tool.parameters.properties).filter(([key]) => key !== "config")) : undefined;
    pi.registerTool({ ...tool,
      ...(scan ? {
        description: "Read-only AST rule scanning using explicit inline rule_yaml or rule_file. Project config overrides and automatic project rules are disabled.",
        promptGuidelines: ["Supply rule_yaml or rule_file explicitly. Native custom languages and project sgconfig discovery are disabled."],
        parameters: { ...tool.parameters, properties, additionalProperties: false,
          ...(tool.parameters.required ? { required: tool.parameters.required.filter(key => key !== "config") } : {}) },
      } : {}),
      async execute(...args) {
      if (scan && Object.hasOwn(args[1] ?? {}, "config")) throw new Error("Project config is not available in read-only AST");
      const result = await tool.execute(...args);
      track(result);
      return result;
    } });
  }
  pi.on("session_start", async (_event, ctx) => {
    const version = await pi.exec(binary, ["--version"], { timeout: 5000 });
    if (version.code !== 0) throw new Error("Pinned ast-grep is unavailable; no runtime installer is permitted");
    ctx.ui.setStatus("ast-grep", "ast-grep RO");
  });
}
