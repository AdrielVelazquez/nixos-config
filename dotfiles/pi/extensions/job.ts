// Background jobs as a tool: start a command, keep working, read its output when it matters, stop it.
//
//   job start   {command, name?}   run a command in the background; returns its id
//   job list                       every job with its state
//   job output  {id, since?, tail?, wait?}   what it printed; `wait` seconds blocks for news or its end
//   job stop    {id}               end it (the whole process group)
//
// The interactive session only: a job runs with the user's authority, like bash, and the read-only roles have no shell.
// Jobs end with the session. `/jobs` lists them and `/jobs stop <id|all>` ends them.
import { StringEnum } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";
import { JobManager, describeJob, type JobInfo, type JobOptions } from "./job-core.ts";

const Parameters = Type.Object({
  op: StringEnum(["start", "list", "output", "stop"] as const, {
    description: "start runs `command` in the background; list shows every job; output reads a job's output; stop ends a job.",
  }),
  command: Type.Optional(Type.String({ description: "The shell command, for start." })),
  name: Type.Optional(Type.String({ description: "A short label, for start." })),
  id: Type.Optional(Type.Number({ description: "The job number shown as #id, for output and stop." })),
  since: Type.Optional(Type.Number({ description: "For output: the `cursor` of the previous read, to get only what is new. Default 0: everything still kept." })),
  tail: Type.Optional(Type.Number({ description: "For output: only the last N lines." })),
  wait: Type.Optional(Type.Number({ description: "For output: wait up to this many seconds (at most 120) for new output or for the job to end." })),
});

const MAX_WAIT_SECONDS = 120;
/** The most one `output` call returns; `since` with the returned cursor reads on from there. */
const MAX_READ_CHARS = 48 * 1024;

export function createJobs(pi: ExtensionAPI, options: JobOptions & { notifyOnExit: boolean }) {
  let manager: JobManager | undefined;
  let current: ExtensionContext | undefined;

  // A callback can outlive its session: a job that exits as the session ends reports to a context Pi has already
  // retired, and touching that context throws. Reporting is best effort.
  const report = (action: (ctx: ExtensionContext) => void) => {
    if (!current) return;
    try {
      if (current.hasUI) action(current);
    } catch {
      // The session is gone; there is nobody to tell.
    }
  };
  const show = () => report((ctx) => ctx.ui.setStatus("jobs", manager?.running ? `jobs ${manager.running}` : undefined));
  const ensure = (ctx: ExtensionContext): JobManager => {
    current = ctx;
    if (!manager) {
      manager = new JobManager({ ...options, cwd: ctx.cwd });
      manager.onExit = (info: JobInfo) => {
        show();
        if (options.notifyOnExit) report((live) => live.ui.notify(`Job ${describeJob(info)}`, info.exitCode === 0 ? "info" : "warning"));
      };
    }
    return manager;
  };

  pi.on("session_start", (_event, ctx) => {
    current = ctx;
  });
  pi.on("session_shutdown", (_event, ctx) => {
    const ending = manager;
    manager = undefined;
    if (ending) {
      // The jobs end with the session, and nobody is left to announce it.
      ending.onExit = undefined;
      ending.stopAll();
    }
    if (ctx.hasUI) ctx.ui.setStatus("jobs", undefined);
    current = undefined;
  });

  pi.registerTool({
    name: "job",
    label: "Job",
    description: [
      "Run commands in the background while you keep working: a build, a test watcher, a dev server.",
      "`start` (command, name?) returns a job id at once; `list` shows every job; `output` (id, since?, tail?, wait?) returns what the job printed, stdout and stderr together, and a `cursor` to pass as `since` next time; `stop` (id) ends it.",
      `\`output\` with \`wait\` seconds (at most ${MAX_WAIT_SECONDS}) blocks until the job prints something new or ends, so check in with it instead of polling in a loop.`,
      "Jobs run in the project directory with your authority, like bash, and end with the session.",
    ].join("\n"),
    promptSnippet: "job: run a command in the background and read its output later (start, list, output, stop)",
    promptGuidelines: ["Use `job` for commands that take minutes or never exit (builds, servers, watchers) so you can keep working; use bash for anything short."],
    parameters: Parameters,
    executionMode: "sequential",
    async execute(_id, params, signal, _update, ctx) {
      const jobs = ensure(ctx);
      switch (params.op) {
        case "start": {
          if (typeof params.command !== "string") throw new Error("`start` needs a `command`");
          const info = jobs.start(params.command, params.name);
          show();
          return { content: [{ type: "text", text: `Started ${describeJob(info)} (pid ${info.pid}). Read it with output id=${info.id}.` }], details: { id: info.id } };
        }
        case "list": {
          const all = jobs.list();
          return { content: [{ type: "text", text: all.length ? all.map((info) => describeJob(info)).join("\n") : "No jobs." }], details: undefined };
        }
        case "output": {
          if (typeof params.id !== "number") throw new Error("`output` needs the job `id`");
          const waitMs = Math.min(Math.max(params.wait ?? 0, 0), MAX_WAIT_SECONDS) * 1000;
          const read = await jobs.output(params.id, { since: params.since, tail: params.tail, limit: MAX_READ_CHARS, waitMs, signal });
          const lines = [describeJob(read.info), `cursor: ${read.cursor}`];
          if (read.dropped) lines.push(`(${read.dropped} characters before this were dropped from the buffer)`);
          if (read.truncated) lines.push(`(output cut at ${MAX_READ_CHARS} characters: read on with since=${read.cursor})`);
          return { content: [{ type: "text", text: `${lines.join("\n")}\n---\n${read.text || "(no new output)"}` }], details: undefined };
        }
        case "stop": {
          if (typeof params.id !== "number") throw new Error("`stop` needs the job `id`");
          const info = await jobs.stop(params.id);
          show();
          return { content: [{ type: "text", text: `Stopped ${describeJob(info)}` }], details: undefined };
        }
        default:
          throw new Error(`Unknown operation "${String(params.op)}"; use start, list, output or stop`);
      }
    },
    renderCall(args, theme) {
      const detail = args.op === "start" ? (args.name ?? args.command ?? "") : args.id !== undefined ? `#${args.id}` : "";
      return new Text(theme.fg("toolTitle", theme.bold("job ")) + theme.fg("accent", args.op) + (detail ? theme.fg("muted", ` ${String(detail).slice(0, 60)}`) : ""), 0, 0);
    },
  });

  pi.registerCommand("jobs", {
    description: "List the background jobs; `/jobs stop <id|all>` ends one or all",
    handler: async (args, ctx) => {
      const jobs = ensure(ctx);
      const [verb, target] = args.trim().split(/\s+/);
      if (verb === "stop") {
        const ids = target === "all" ? jobs.list().filter((info) => info.running).map((info) => info.id) : [Number(target)];
        if (ids.some((id) => !Number.isInteger(id))) return ctx.ui.notify("Usage: /jobs stop <id|all>", "warning");
        for (const id of ids) await jobs.stop(id);
        show();
        return ctx.ui.notify(ids.length ? `Stopped ${ids.length} job${ids.length === 1 ? "" : "s"}` : "No job is running", "info");
      }
      const all = jobs.list();
      ctx.ui.notify(all.length ? all.map((info) => describeJob(info)).join("\n") : "No background jobs", "info");
    },
  });
}

export default function jobs(pi: ExtensionAPI) {
  createJobs(pi, { shell: ["/bin/sh", "-c"], cwd: process.cwd(), maxJobs: 8, maxBuffer: 1024 * 1024, notifyOnExit: true });
}
