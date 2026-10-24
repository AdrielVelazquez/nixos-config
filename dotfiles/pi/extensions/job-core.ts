// Background jobs for Pi: commands that keep running while the conversation goes on. A job is a shell command in its
// own process group, its stdout and stderr kept in a bounded buffer the model reads in pieces. No Pi runtime state
// lives here, so the manager is exercised by a plain node test with real processes.
import { spawn, type ChildProcess } from "node:child_process";
import { StringDecoder } from "node:string_decoder";

export interface JobOptions {
  /** The shell and its flag, for example `["/bin/sh", "-c"]`; the command is appended. */
  shell: string[];
  cwd: string;
  env?: Record<string, string | undefined>;
  /** Most jobs running at once. */
  maxJobs: number;
  /** Output kept per job, in characters; older output is dropped. */
  maxBuffer: number;
}

export interface JobInfo {
  id: number;
  name: string;
  command: string;
  pid: number | undefined;
  startedAt: number;
  endedAt?: number;
  running: boolean;
  exitCode?: number | null;
  signal?: string | null;
}

export interface JobOutput {
  text: string;
  /** Pass as `since` next time to read only what arrives after this call. */
  cursor: number;
  /** Characters that fell out of the buffer before `since`, so the reader knows it missed some. */
  dropped: number;
  info: JobInfo;
}

class Job {
  readonly info: JobInfo;
  readonly child: ChildProcess;
  buffer = "";
  /** Characters ever received minus those still in `buffer`. */
  base = 0;
  readonly waiters = new Set<() => void>();
  readonly closed: Promise<void>;

  private readonly maxBuffer: number;

  // No parameter properties: the module is imported by plain node in the tests, which only strips types.
  constructor(info: JobInfo, child: ChildProcess, maxBuffer: number) {
    this.info = info;
    this.child = child;
    this.maxBuffer = maxBuffer;
    const append = (chunk: string) => {
      this.buffer += chunk;
      if (this.buffer.length > this.maxBuffer) {
        const cut = this.buffer.length - this.maxBuffer;
        this.buffer = this.buffer.slice(cut);
        this.base += cut;
      }
      this.wake();
    };
    for (const stream of [child.stdout, child.stderr]) {
      const decoder = new StringDecoder("utf8");
      stream?.on("data", (data: Buffer) => append(decoder.write(data)));
      stream?.on("end", () => append(decoder.end()));
    }
    this.closed = new Promise((resolve) => {
      child.once("close", (code, signal) => {
        this.info.running = false;
        this.info.endedAt = Date.now();
        this.info.exitCode = code;
        this.info.signal = signal;
        this.wake();
        resolve();
      });
    });
    child.once("error", () => {
      this.info.running = false;
      this.info.endedAt = Date.now();
      this.info.exitCode = null;
      this.wake();
    });
  }

  get length(): number {
    return this.base + this.buffer.length;
  }

  wake() {
    for (const waiter of [...this.waiters]) waiter();
  }
}

export class JobManager {
  private readonly jobs = new Map<number, Job>();
  private next = 1;
  private readonly options: JobOptions;
  /** Called once when a job exits, however it ended. */
  onExit: ((info: JobInfo) => void) | undefined;

  constructor(options: JobOptions) {
    this.options = options;
  }

  start(command: string, name?: string): JobInfo {
    if (!command.trim()) throw new Error("A job needs a command");
    const running = [...this.jobs.values()].filter((job) => job.info.running).length;
    if (running >= this.options.maxJobs) throw new Error(`${running} jobs are already running (the limit is ${this.options.maxJobs}); stop one first`);
    const [shell, ...flags] = this.options.shell;
    const child = spawn(shell, [...flags, command], {
      cwd: this.options.cwd,
      env: { ...process.env, ...this.options.env } as NodeJS.ProcessEnv,
      detached: true,
      stdio: ["ignore", "pipe", "pipe"],
    });
    const id = this.next++;
    const info: JobInfo = { id, name: name?.trim() || command.trim().split("\n")[0].slice(0, 40), command, pid: child.pid, startedAt: Date.now(), running: true };
    const job = new Job(info, child, this.options.maxBuffer);
    this.jobs.set(id, job);
    job.closed.then(() => this.onExit?.(info));
    return { ...info };
  }

  private get(id: number): Job {
    const job = this.jobs.get(id);
    if (!job) throw new Error(`There is no job #${id}; \`list\` shows the jobs`);
    return job;
  }

  list(): JobInfo[] {
    return [...this.jobs.values()].map((job) => ({ ...job.info }));
  }

  get running(): number {
    return [...this.jobs.values()].filter((job) => job.info.running).length;
  }

  /**
   * What a job printed, from `since` (0 reads everything still buffered) or the last `tail` lines. With `waitMs` the
   * call also waits, up to that long, for output past `since` or for the job to end, so a model need not poll.
   */
  async output(id: number, options: { since?: number; tail?: number; waitMs?: number; signal?: AbortSignal } = {}): Promise<JobOutput> {
    const job = this.get(id);
    const since = options.since ?? 0;
    if (options.waitMs && job.info.running && job.length <= since) {
      await new Promise<void>((resolve) => {
        const done = () => {
          clearTimeout(timer);
          job.waiters.delete(check);
          options.signal?.removeEventListener("abort", done);
          resolve();
        };
        const check = () => {
          if (!job.info.running || job.length > since) done();
        };
        const timer = setTimeout(done, options.waitMs);
        job.waiters.add(check);
        options.signal?.addEventListener("abort", done, { once: true });
      });
    }
    const from = Math.max(since, job.base);
    let text = job.buffer.slice(from - job.base);
    if (options.tail !== undefined) {
      const lines = text.split("\n");
      const kept = lines.slice(-Math.max(1, options.tail) - (text.endsWith("\n") ? 1 : 0));
      text = kept.join("\n");
    }
    return { text, cursor: job.length, dropped: Math.max(0, job.base - since), info: { ...job.info } };
  }

  /** End a job: its whole process group gets SIGTERM, then SIGKILL if it is still there after `graceMs`. */
  async stop(id: number, graceMs = 3000): Promise<JobInfo> {
    const job = this.get(id);
    if (job.info.running) {
      this.signal(job, "SIGTERM");
      const killer = setTimeout(() => this.signal(job, "SIGKILL"), graceMs);
      await job.closed;
      clearTimeout(killer);
    }
    return { ...job.info };
  }

  /** Kill everything at once, for a session that is ending. */
  stopAll(): void {
    for (const job of this.jobs.values()) if (job.info.running) this.signal(job, "SIGKILL");
  }

  private signal(job: Job, signal: NodeJS.Signals) {
    try {
      // A negative pid addresses the process group, so the command's own children go too.
      if (job.child.pid) process.kill(-job.child.pid, signal);
    } catch {
      // Already gone.
    }
  }
}

export function formatAge(ms: number): string {
  const seconds = Math.round(ms / 1000);
  if (seconds < 60) return `${seconds}s`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
  return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`;
}

/** `#2 nix build · running 1m 12s`, `#1 npm test · exit 1 after 4s`, `#3 server · killed by SIGTERM after 9s`. */
export function describeJob(info: JobInfo, now = Date.now()): string {
  const age = formatAge((info.endedAt ?? now) - info.startedAt);
  const state = info.running ? `running ${age}` : info.signal ? `killed by ${info.signal} after ${age}` : `exit ${info.exitCode ?? "?"} after ${age}`;
  return `#${info.id} ${info.name} · ${state}`;
}
