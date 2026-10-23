import { lstat, readFile, writeFile } from 'node:fs/promises';
import { relative } from 'node:path';
import { withFileMutationQueue, type ExtensionAPI, type ExtensionContext } from '@earendil-works/pi-coding-agent';
import { isInside, lineDiff, resolveToolPath, runFormatter, selectFormatter, type FormatterSpec } from './format-core.ts';

export type FormatOptions = {
  formatters: FormatterSpec[];
  timeoutMs: number;
  maxFileBytes: number;
  maxOutputBytes: number;
  maxDiffLines: number;
  /** Total formatting time for one tool result that changed many files; defaults to six formatter deadlines. */
  budgetMs?: number;
};

/** The files a successful tool result says it wrote. A rewrite preview, or any other tool, wrote none. */
function writtenFiles(event: { toolName: string; input?: Record<string, unknown>; details?: unknown }): string[] {
  if (event.toolName === 'edit' || event.toolName === 'write') return typeof event.input?.path === 'string' ? [event.input.path] : [];
  const details = event.details as { changes_applied?: unknown; applied?: unknown } | undefined;
  if (event.toolName !== 'ast_grep_rewrite' || details?.changes_applied !== true || !Array.isArray(details.applied)) return [];
  return details.applied.map(entry => entry?.file).filter((file): file is string => typeof file === 'string');
}

/**
 * Format files the model just wrote. Register before the LSP extension: Pi runs `tool_result` handlers in load
 * order, so diagnostics then describe the formatted bytes.
 */
export function createFormatOnWrite(pi: ExtensionAPI, options: FormatOptions) {
  const unavailable = new Set<string>();
  const budgetMs = options.budgetMs ?? options.timeoutMs * 6;

  async function formatFile(requested: string, ctx: ExtensionContext, named: boolean): Promise<string | undefined> {
    const absPath = resolveToolPath(requested, ctx.cwd);
    if (!isInside(ctx.cwd, absPath)) return undefined;
    const spec = selectFormatter(options.formatters.filter(candidate => !unavailable.has(candidate.name)), absPath, ctx.cwd);
    if (!spec) return undefined;
    return withFileMutationQueue(absPath, async () => {
      const info = await lstat(absPath).catch(() => undefined);
      if (!info?.isFile() || info.size > options.maxFileBytes) return undefined;
      let original: string;
      try {
        original = new TextDecoder('utf-8', { fatal: true }).decode(await readFile(absPath));
      } catch {
        return undefined;
      }
      const result = await runFormatter(spec, { absPath, input: original, timeoutMs: options.timeoutMs, maxOutputBytes: options.maxOutputBytes, root: ctx.cwd });
      if (!result.ok) {
        if (result.missing && !unavailable.has(spec.name)) {
          unavailable.add(spec.name);
          ctx.ui.notify(`Format-on-write: ${spec.name} is unavailable (${result.reason}); skipping it for this session.`, 'warning');
        }
        return undefined;
      }
      if (result.output === original || (result.output === '' && original !== '')) return undefined;
      await writeFile(absPath, result.output);
      const diff = lineDiff(original, result.output, { maxLines: options.maxDiffLines });
      if (!diff) return undefined;
      const subject = named ? `${relative(ctx.cwd, absPath)} ` : '';
      return `Formatted ${subject}with ${spec.name}: +${diff.added}/-${diff.removed} lines. The file on disk now includes the formatter's changes below; base any later edit on this content. Anchors (LINE#HASH) from before this note are stale: re-read the file before an edit that uses them.\n${diff.text}`;
    });
  }

  pi.on('tool_result', async (event, ctx) => {
    if (event.isError) return undefined;
    const files = writtenFiles(event);
    const named = event.toolName !== 'edit' && event.toolName !== 'write';
    const started = Date.now();
    const reports: string[] = [];
    for (const [index, file] of files.entries()) {
      if (Date.now() - started > budgetMs) {
        const left = files.length - index;
        reports.push(`${left} more changed file${left === 1 ? ' was' : 's were'} not formatted: the ${Math.round(budgetMs / 1000)} s formatting budget for one tool result was used up.`);
        break;
      }
      const report = await formatFile(file, ctx, named);
      if (report !== undefined) reports.push(report);
    }
    return reports.length === 0 ? undefined : { content: [...event.content, { type: 'text' as const, text: reports.join('\n\n') }] };
  });
}
