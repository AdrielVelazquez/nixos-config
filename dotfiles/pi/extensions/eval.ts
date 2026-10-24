import { mkdtemp, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Type } from 'typebox';
import { DEFAULT_MAX_BYTES, DEFAULT_MAX_LINES, formatSize, truncateTail, type ExtensionAPI, type ExtensionContext } from '@earendil-works/pi-coding-agent';
import { Text } from '@earendil-works/pi-tui';
import { endNotices, reachedTools, toolAnswer } from './eval-core.ts';
import { Kernel, type ToolAnswer } from './eval-kernel.ts';

export type EvalOptions = {
  python: string;
  runner: string;
  defaultTimeoutSeconds: number;
  maxTimeoutSeconds: number;
  maxOutputBytes: number;
};

const Parameters = Type.Object({
  code: Type.String({ description: 'Python source for one cell. Top-level statements run in the persistent namespace; a final expression is printed.' }),
  timeout: Type.Optional(Type.Number({ minimum: 1, description: 'Seconds before the cell is interrupted. Default 120.' })),
  reset: Type.Optional(Type.Boolean({ description: 'Start a fresh kernel before running the cell, discarding every variable.' })),
});

type CellDetails = { durationMs: number; toolCalls: number; truncated: boolean; fullOutputPath?: string; notices: string[] };

/** A session entry that records an `eval` tool result. */
function isEvalResult(entry: unknown): boolean {
  if (typeof entry !== 'object' || entry === null || !('type' in entry) || entry.type !== 'message' || !('message' in entry)) return false;
  const message = entry.message;
  return typeof message === 'object' && message !== null && 'role' in message && message.role === 'toolResult' && 'toolName' in message && message.toolName === 'eval';
}

/** Whether this session already holds `eval` results, so the model may believe in variables a new process lacks. */
function hasEarlierCells(ctx: ExtensionContext): boolean {
  try {
    return ctx.sessionManager.getBranch().some(isEvalResult);
  } catch {
    return false;
  }
}

/**
 * The `eval` tool: a persistent Python kernel for the interactive session. Cells call back into the session's other
 * tools through `ctx.executeTool`, so formatting, diagnostics and anchors apply to what they write.
 */
export function createEval(pi: ExtensionAPI, options: EvalOptions) {
  let kernel: Kernel | undefined;
  let everStarted = false;
  // Set when a result already told the model that the kernel's variables are gone.
  let lossReported = false;
  const stop = () => { kernel?.kill(); kernel = undefined; everStarted = false; lossReported = false; };
  pi.on('session_start', stop);
  pi.on('session_shutdown', stop);

  pi.registerTool({
    name: 'eval',
    label: 'eval',
    description: [
      'Run one Python cell in a persistent kernel. Variables, functions and imports stay defined across calls for as long as this Pi process lives, compaction included.',
      'The kernel is plain Python (standard library only), not IPython: no `!cmd`, `%magics` or top-level `await`. A final expression is printed. Output is stdout and stderr, children included; a traceback leaves the kernel running.',
      'Helpers: `tool.<name>(**args)` calls any callable tool through the same pipeline as a direct call and returns its text, structured value or parts (raises ToolError; `tool.eval` is refused).',
      '`read(path, offset?, limit?)` is raw file text with no line anchors; `write(path, content)` goes through the write tool; `env(key?, value?)`; `image(path|bytes)` attaches an image; `state()` lists the variables and imports defined so far.',
      `Output keeps the last ${DEFAULT_MAX_LINES} lines or ${formatSize(DEFAULT_MAX_BYTES)}; the full text is saved to a file. \`timeout\` (default ${options.defaultTimeoutSeconds}s) interrupts the cell; a kernel that ignores the interrupt is killed and its variables are lost. \`reset: true\` starts a fresh kernel.`,
    ].join('\n'),
    promptSnippet: 'eval: run Python cells in a persistent kernel (variables survive between calls; `tool.<name>()` calls other tools)',
    promptGuidelines: ['After a context compaction or a kernel-loss notice, run `state()` before assuming eval variables exist, and do not repeat setup that already succeeded.'],
    parameters: Parameters,
    executionMode: 'sequential',
    reachesTools: input => reachedTools(String(input.code ?? '')),
    async execute(_id, params, signal, _update, ctx) {
      const notices: string[] = [];
      if (params.reset && kernel) {
        kernel.kill();
        kernel = undefined;
        notices.push('The kernel was reset; every variable is gone.');
      }
      if (kernel && !kernel.alive) kernel = undefined;
      if (!kernel) {
        if (!params.reset && !lossReported) {
          if (everStarted) notices.push('A fresh Python kernel started; variables from earlier cells are gone.');
          else if (hasEarlierCells(ctx)) notices.push('A fresh Python kernel started for this Pi process; variables from earlier eval calls in this session are gone.');
        }
        lossReported = false;
        kernel = new Kernel({ python: options.python, runner: options.runner, cwd: ctx.cwd, env: process.env, maxOutputBytes: options.maxOutputBytes });
        everStarted = true;
      }
      const timeoutSeconds = Math.min(params.timeout ?? options.defaultTimeoutSeconds, options.maxTimeoutSeconds);
      const started = performance.now();
      const call = async (name: string, args: unknown, callSignal: AbortSignal): Promise<ToolAnswer> => {
        if (name === 'eval') return { ok: false, error: 'tool.eval is not callable from eval' };
        try {
          return toolAnswer(await ctx.executeTool(name, args, { signal: callSignal }));
        } catch (error) {
          return { ok: false, error: error instanceof Error ? error.message : String(error) };
        }
      };
      let result;
      try {
        result = await kernel.run(params.code, { timeoutMs: timeoutSeconds * 1000, signal, call });
      } catch (error) {
        kernel.kill();
        kernel = undefined;
        throw error;
      }
      if (result.died) { kernel = undefined; lossReported = true; }

      const truncation = truncateTail(result.output, { maxLines: DEFAULT_MAX_LINES, maxBytes: DEFAULT_MAX_BYTES });
      const details: CellDetails = { durationMs: Math.round(performance.now() - started), toolCalls: result.toolCalls, truncated: truncation.truncated, notices };
      let output = truncation.content;
      if (truncation.truncated) {
        const dir = await mkdtemp(join(tmpdir(), 'pi-eval-'));
        details.fullOutputPath = join(dir, 'output.txt');
        await writeFile(details.fullOutputPath, result.output, 'utf8');
        output += `\n[Output truncated: showing the last ${truncation.outputLines} of ${truncation.totalLines} lines (${formatSize(truncation.outputBytes)} of ${formatSize(truncation.totalBytes)}). Full output: ${details.fullOutputPath}]`;
      }
      const closing = endNotices(result, timeoutSeconds, Math.round(options.maxOutputBytes / 1048576));
      details.notices = [...notices, ...closing];
      const text = [...notices, output.replace(/\n+$/, ''), ...closing].filter(part => part !== '').join('\n') || '(no output)';
      if (!result.ok) throw new Error(text);
      return { content: [{ type: 'text', text }, ...result.images.map(image => ({ type: 'image' as const, data: image.data, mimeType: image.mimeType }))], details };
    },
    renderCall(args, theme) {
      const lines = String(args.code ?? '').split('\n');
      const shown = lines.slice(0, 12).map(line => '  ' + theme.fg('muted', line));
      if (lines.length > shown.length) shown.push('  ' + theme.fg('dim', `… ${lines.length - shown.length} more lines`));
      const header = theme.fg('toolTitle', theme.bold('eval ')) + theme.fg('dim', 'python') + (args.reset ? theme.fg('accent', ' reset') : '');
      return new Text([header, ...shown].join('\n'), 0, 0);
    },
  });
}
