import { rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export const AST_READ_TOOLS = ["ast_grep_run", "ast_grep_scan", "ast_grep_outline", "ast_grep_debug_query", "ast_grep_languages"];

export function installReadOnlyAst(pi: ExtensionAPI, createTools, binary: string, configFile: string) {
  // Ignore ambient AST_GREP_BIN and project sgconfig/custom native grammars.
  const runner = (_binary, args, options = {}) => pi.exec(binary, ["--custom-languages", "ignore", "--config", configFile, ...args], {
    cwd: options.cwd, signal: options.signal, timeout: options.timeoutMs,
  });
  const tools = createTools(runner), spills = new Set<string>();
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
      const file = result.details?.fullOutputPath;
      if (typeof file === "string" && dirname(dirname(file)) === tmpdir() && basename(dirname(file)).startsWith("pi-ast-grep-")) spills.add(dirname(file));
      return result;
    } });
  }
  pi.on("session_start", async (_event, ctx) => {
    const version = await pi.exec(binary, ["--version"], { timeout: 5000 });
    if (version.code !== 0) throw new Error("Pinned ast-grep is unavailable; no runtime installer is permitted");
    ctx.ui.setStatus("ast-grep", `${version.stdout.trim()} (read-only)`);
  });
  pi.on("session_shutdown", async () => {
    await Promise.all([...spills].map(dir => rm(dir, { recursive: true, force: true })));
    spills.clear();
  });
}
