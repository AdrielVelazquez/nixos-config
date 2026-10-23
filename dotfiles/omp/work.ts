import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { createProviderService } from "./provider-core.mjs";
import { toolDecision, spawnDecision } from "./policy.mjs";
import { readProjectSelection } from "./reddit-state.mjs";
import { createRedditServices } from "./reddit-services.mjs";
import { createRedditTools } from "./reddit-tools.mjs";
import { registerReddit } from "./reddit-ui.ts";

const execute = promisify(execFile);
const SERVICES = Symbol.for("nix-managed-omp-process-services-v1");

/** OMP native extension, not an OpenCode plugin or modern upstream-Pi provider. */
export async function installWork(pi, options) {
  // Native markdown tool lists don't filter inherited MCP/extension/xdev tools.
  pi.on("tool_call", (event, ctx) => toolDecision(event, ctx));
  pi.on("before_subagent_spawn", (event, ctx) => spawnDecision(options.routes, event, ctx));
  const reddit = options.reddit ? { ...options.reddit,
    agentDir: process.env.PI_CODING_AGENT_DIR || options.reddit.agentDir,
    extensionSource: options.extensionSource } : undefined;
  let providerService, providerSetupError, servicesPromise, toolsPromise;

  // OMP discards an entire extension if its factory throws. Keep the policy
  // handlers installed even when auth/acquisition/provider setup is unavailable.
  try {
    const services = globalThis[SERVICES] ??= new Map();
    const agentDir = options.reddit ? process.env.PI_CODING_AGENT_DIR || options.reddit.agentDir : "";
    // Preferences are read only for a new process service. Children must inherit
    // the live project even if another session later edits that directory choice.
    const serviceKey = `${options.manifest}\0${process.cwd()}\0${agentDir}\0${options.projectId ?? ""}\0${process.env.LLM_PLATFORM_PROJECT_ID ?? ""}`;
    let service = services.get(serviceKey);
    if (!service) {
      const configured = options.projectSelection ?? { id: options.projectId, source: "configured", locked: true };
      const selected = options.reddit ? await readProjectSelection(agentDir, process.cwd(), configured) : configured;
      service = createProviderService({ gatewayOrigin: options.gatewayOrigin, projectId: selected.id, projectSource: selected.source,
        allowTestLoopback: options.allowTestLoopback === true,
        requiredModels: [...new Set(Object.values(options.routes ?? {}).map((value: string) => value.replace(/^llmplatform\//, "").replace(/:(off|minimal|low|medium|high|xhigh|max)$/, "")))],
      }, {
        acquire: async () => {
          let stdout;
          try {
            ({ stdout } = await execute(options.python, ["-E", options.helper, "--config", options.manifest, "--acquire", String(process.pid)],
              { timeout: 100000, maxBuffer: 1024 * 1024, env: { ...process.env, PYTHONPATH: "", PYTHONHOME: "" } }));
          } catch (error) {
            throw new Error(`Owned Headroom acquisition failed: ${String(error.stderr || error.message).trim().slice(-140)}`);
          }
          const owned = JSON.parse(stdout);
          process.env.HEADROOM_PROXY_URL = owned.proxyURL;
          process.env.HEADROOM_OMP_MEMORY_DB = owned.memoryDB;
          process.env.HEADROOM_OMP_PROJECT = owned.project;
          return owned;
        },
      });
      services.set(serviceKey, service);
    }
    providerService = service;
    const config = await service.providerConfig();
    const models = config.models.length ? config.models : await service.fetchModels();
    pi.registerProvider("llmplatform", { ...config, models });
  } catch (error) {
    providerSetupError = error;
    const message = `LLM Platform is unavailable: ${String(error.message).slice(0, 240)}. Worker gates remain active; restart OMP after fixing access.`;
    pi.on("session_start", (_event, ctx) => ctx.ui.notify(message, "error"));
  }
  if (reddit) {
    const main = ctx => { if (ctx.agent?.kind !== "main") throw new Error("Reddit controls are main-session only"); };
    const getServices = async ctx => {
      main(ctx);
      if (!providerService) throw providerSetupError ?? new Error("LLM Platform provider is unavailable");
      if (!servicesPromise) servicesPromise = createRedditServices({ ...reddit, provider: providerService,
        projectSelection: options.projectSelection ?? { id: options.projectId, source: "configured", locked: true } }, {
        registerProvider: config => pi.registerProvider("llmplatform", config), setModel: model => pi.setModel(model),
      }).catch(error => { servicesPromise = undefined; throw error; });
      return servicesPromise;
    };
    const getTools = async ctx => {
      main(ctx);
      if (!toolsPromise) toolsPromise = createRedditTools(pi, reddit).catch(error => { toolsPromise = undefined; throw error; });
      const controller = await toolsPromise;
      await controller.start(ctx);
      return controller;
    };
    registerReddit(pi, { services: getServices, tools: getTools });
    pi.on("session_start", async (_event, ctx) => {
      if (ctx.agent?.kind !== "main") return;
      for (const initialize of [getServices, getTools]) {
        try { await initialize(ctx); }
        catch (error) { ctx.ui.notify(`Reddit controls unavailable: ${String(error.message).slice(0, 240)}`, "warning"); }
      }
    });
    pi.on("session_shutdown", async (_event, ctx) => {
      if (ctx.agent?.kind === "main" && servicesPromise) await servicesPromise.then(service => service.close()).catch(() => {});
    });
  } else pi.registerCommand("llmplatform", { description: "Refresh or inspect the managed LLM Platform catalog", handler: async (args, ctx) => {
    if (args.trim() === "refresh") await ctx.modelRegistry.refreshProvider("llmplatform", "online");
    ctx.ui.notify("LLM Platform uses WARP project authentication and an owned Headroom inference proxy. Native model selection is available through /model.", "info");
  } });
  // No API/UI context is stored in the process-shared service. Children rebind
  // this factory, while the PID lease lives until the OMP process actually exits.
  pi.on("before_agent_start", (event, ctx) => {
    if (ctx.agent?.kind !== "main") return;
    return { systemPrompt: [...event.systemPrompt, ...(options.bootstrap ? [options.bootstrap] : [])] };
  });
}
