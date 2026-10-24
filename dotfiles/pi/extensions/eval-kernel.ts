import { spawn, type ChildProcess } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { createInterface } from 'node:readline';

export type KernelImage = { type: 'image'; data: string; mimeType: string };
export type ToolAnswer = { ok: true; value: unknown } | { ok: false; error: string };
/** Answers a `tool.<name>(...)` call a cell made. Never rejects: failures are `{ ok: false }`. */
export type ToolCaller = (name: string, args: unknown, signal: AbortSignal) => Promise<ToolAnswer>;

export type CellResult = {
  ok: boolean;
  /** Everything the cell printed, stderr and child processes included, in the order it arrived. */
  output: string;
  images: KernelImage[];
  timedOut: boolean;
  cancelled: boolean;
  /** The kernel process exited before the cell finished; its namespace is gone. */
  died: boolean;
  /** The cell printed more than `maxOutputBytes` and was interrupted. */
  overflow: boolean;
  toolCalls: number;
  /** How the process ended, when it did. */
  exit?: string;
};

export type KernelOptions = {
  python: string;
  runner: string;
  cwd: string;
  env?: NodeJS.ProcessEnv;
  /** How long to wait for the interpreter to come up. */
  startupMs?: number;
  /** How long an interrupted cell may take to stop before the kernel is killed. */
  graceMs?: number;
  maxOutputBytes?: number;
};

export type RunOptions = { timeoutMs?: number; signal?: AbortSignal; call: ToolCaller };

type Active = {
  id: number;
  marker: Buffer;
  chunks: Buffer[];
  bytes: number;
  tail: Buffer;
  outputComplete: boolean;
  done?: { ok: boolean; images: KernelImage[] };
  timedOut: boolean;
  cancelled: boolean;
  overflow: boolean;
  toolCalls: number;
  controller: AbortController;
  call: ToolCaller;
  finish: (result: CellResult) => void;
};

/**
 * One Python process whose namespace survives from cell to cell (`runner.py` holds the protocol). Cells run one at
 * a time. A process group is used so that an interrupt or a kill reaches the children a cell started, as Ctrl+C would.
 */
export class Kernel {
  private readonly child: ChildProcess;
  private readonly nonce = randomBytes(8).toString('hex');
  private readonly ready: Promise<void>;
  private readonly maxOutputBytes: number;
  private readonly graceMs: number;
  private active?: Active;
  private queue: Promise<unknown> = Promise.resolve();
  private nextId = 0;
  private exited?: string;
  private stderr = '';
  private killTimer?: NodeJS.Timeout;

  constructor(options: KernelOptions) {
    this.maxOutputBytes = options.maxOutputBytes ?? 64 * 1024 * 1024;
    this.graceMs = options.graceMs ?? 5000;
    this.child = spawn(options.python, ['-I', '-u', options.runner, this.nonce], {
      cwd: options.cwd,
      env: options.env ?? process.env,
      stdio: ['ignore', 'pipe', 'pipe', 'pipe', 'pipe'],
      detached: true,
    });
    const startup = { resolve: () => {}, reject: (_error: Error) => {} };
    this.ready = new Promise<void>((resolve, reject) => { startup.resolve = resolve; startup.reject = reject; });
    this.ready.catch(() => {});
    const timer = setTimeout(() => startup.reject(new Error(`The Python kernel did not start within ${options.startupMs ?? 30000} ms${this.detail()}`)), options.startupMs ?? 30000);
    this.ready.finally(() => clearTimeout(timer)).catch(() => {});
    for (const stream of [this.child.stdin, this.child.stdout, this.child.stderr, this.child.stdio[3], this.child.stdio[4]]) stream?.on('error', () => {});
    this.child.stdout!.on('data', (chunk: Buffer) => this.onOutput(chunk));
    this.child.stderr!.on('data', (chunk: Buffer) => { if (this.stderr.length < 65536) this.stderr += chunk.toString('utf8'); });
    createInterface({ input: this.child.stdio[4]! }).on('line', line => this.onControl(line, startup.resolve));
    this.child.on('error', error => { this.exited = `failed to start: ${error.message}`; startup.reject(new Error(`The Python kernel failed to start: ${error.message}`)); this.settle(true); });
    this.child.on('exit', (code, signal) => {
      this.exited = signal ? `killed by ${signal}` : `exit status ${code}`;
      clearTimeout(this.killTimer);
      startup.reject(new Error(`The Python kernel exited before it was ready (${this.exited})${this.detail()}`));
      this.settle(true);
    });
  }

  get alive(): boolean {
    return this.exited === undefined;
  }

  /** Run one cell. Calls queue behind each other. Rejects only when the kernel cannot start. */
  run(code: string, options: RunOptions): Promise<CellResult> {
    const next = this.queue.then(() => this.runNow(code, options));
    this.queue = next.catch(() => {});
    return next;
  }

  /** End the process and everything it started. */
  kill(): void {
    this.signalGroup('SIGKILL');
  }

  private detail(): string {
    const text = this.stderr.trim();
    return text ? `:\n${text.slice(-2000)}` : '';
  }

  private signalGroup(signal: NodeJS.Signals): void {
    const pid = this.child.pid;
    if (pid === undefined) return;
    try { process.kill(-pid, signal); } catch { try { this.child.kill(signal); } catch { /* already gone */ } }
  }

  private async runNow(code: string, options: RunOptions): Promise<CellResult> {
    await this.ready;
    if (this.exited !== undefined) throw new Error(`The Python kernel is not running (${this.exited})`);
    if (options.signal?.aborted) {
      return { ok: false, output: '', images: [], timedOut: false, cancelled: true, died: false, overflow: false, toolCalls: 0 };
    }
    const id = ++this.nextId;
    return new Promise<CellResult>(resolve => {
      const cell: Active = {
        id, marker: Buffer.from(`\0PIEVAL-${this.nonce}-${id}\0`), chunks: [], bytes: 0, tail: Buffer.alloc(0),
        outputComplete: false, timedOut: false, cancelled: false, overflow: false, toolCalls: 0,
        controller: new AbortController(), call: options.call, finish: () => {},
      };
      let timer: NodeJS.Timeout | undefined;
      const onAbort = () => { cell.cancelled = true; this.interrupt(cell); };
      cell.finish = result => {
        clearTimeout(timer);
        clearTimeout(this.killTimer);
        this.killTimer = undefined;
        options.signal?.removeEventListener('abort', onAbort);
        this.active = undefined;
        resolve(result);
      };
      this.active = cell;
      if (options.timeoutMs !== undefined && options.timeoutMs > 0) timer = setTimeout(() => { cell.timedOut = true; this.interrupt(cell); }, options.timeoutMs);
      if (options.signal?.aborted) onAbort(); else options.signal?.addEventListener('abort', onAbort, { once: true });
      this.child.stdio[3]!.write(JSON.stringify({ op: 'run', id, code }) + '\n');
    });
  }

  /** Ctrl+C for the cell; a cell that ignores it is killed after the grace period. */
  private interrupt(cell: Active): void {
    cell.controller.abort();
    this.signalGroup('SIGINT');
    this.killTimer ??= setTimeout(() => { this.killTimer = undefined; if (this.active === cell) this.signalGroup('SIGKILL'); }, this.graceMs);
  }

  private onOutput(chunk: Buffer): void {
    const cell = this.active;
    if (!cell || cell.outputComplete) return;
    const scan = Buffer.concat([cell.tail, chunk]);
    const at = scan.indexOf(cell.marker);
    if (at === -1) {
      // Bytes that might begin the marker are held back until the next chunk shows whether they do.
      const hold = Math.min(cell.marker.length - 1, scan.length);
      this.commit(cell, scan.subarray(0, scan.length - hold));
      cell.tail = Buffer.from(scan.subarray(scan.length - hold));
      return;
    }
    this.commit(cell, scan.subarray(0, at));
    cell.tail = Buffer.alloc(0);
    cell.outputComplete = true;
    this.settle(false);
  }

  private commit(cell: Active, bytes: Buffer): void {
    if (bytes.length === 0) return;
    cell.chunks.push(Buffer.from(bytes));
    cell.bytes += bytes.length;
    if (cell.bytes > this.maxOutputBytes && !cell.overflow) { cell.overflow = true; this.interrupt(cell); }
  }

  private onControl(line: string, ready: () => void): void {
    let message: { op?: string; id?: number; name?: string; args?: unknown; ok?: boolean; images?: KernelImage[] };
    try { message = JSON.parse(line); } catch { return; }
    if (message.op === 'ready') { ready(); return; }
    const cell = this.active;
    if (!cell) return;
    if (message.op === 'done' && message.id === cell.id) {
      cell.done = { ok: message.ok === true, images: message.images ?? [] };
      this.settle(false);
    } else if (message.op === 'call' && typeof message.name === 'string') {
      cell.toolCalls++;
      const id = message.id;
      void cell.call(message.name, message.args, cell.controller.signal).catch((error: unknown) => ({ ok: false as const, error: error instanceof Error ? error.message : String(error) })).then(answer => {
        this.child.stdio[3]!.write(JSON.stringify({ op: 'result', id, ...answer }) + '\n');
      });
    }
  }

  /** Finish the active cell once its output and its `done` message are both in, or when the process is gone. */
  private settle(processGone: boolean): void {
    const cell = this.active;
    if (!cell) return;
    const finished = cell.outputComplete && cell.done !== undefined;
    if (!finished && !processGone) return;
    if (!cell.outputComplete) this.commit(cell, cell.tail);
    const died = !finished;
    cell.finish({
      ok: !died && cell.done!.ok && !cell.timedOut && !cell.cancelled && !cell.overflow,
      output: Buffer.concat(cell.chunks).toString('utf8'),
      images: cell.done?.images ?? [],
      timedOut: cell.timedOut, cancelled: cell.cancelled, died, overflow: cell.overflow, toolCalls: cell.toolCalls,
      exit: died ? this.exited : undefined,
    });
  }
}
