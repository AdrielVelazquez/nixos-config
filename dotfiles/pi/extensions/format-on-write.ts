import { lstat, readFile, writeFile } from 'node:fs/promises';
import { withFileMutationQueue, type ExtensionAPI } from '@earendil-works/pi-coding-agent';
import { isInside, lineDiff, resolveToolPath, runFormatter, selectFormatter, type FormatterSpec } from './format-core.ts';

export type FormatOptions = {
  formatters: FormatterSpec[];
  timeoutMs: number;
  maxFileBytes: number;
  maxOutputBytes: number;
  maxDiffLines: number;
};

/**
 * Format files the model just wrote. Register before the LSP extension: Pi runs `tool_result`
 * handlers in load order, so diagnostics then describe the formatted bytes.
 */
export function createFormatOnWrite(pi: ExtensionAPI, options: FormatOptions) {
  const unavailable = new Set<string>();
  pi.on('tool_result', async (event, ctx) => {
    if (event.isError || (event.toolName !== 'edit' && event.toolName !== 'write')) return undefined;
    const requested = event.input?.path;
    if (typeof requested !== 'string') return undefined;
    const absPath = resolveToolPath(requested, ctx.cwd);
    if (!isInside(ctx.cwd, absPath)) return undefined;
    const spec = selectFormatter(options.formatters.filter(candidate => !unavailable.has(candidate.name)), absPath, ctx.cwd);
    if (!spec) return undefined;

    const report = await withFileMutationQueue(absPath, async () => {
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
      return `Formatted with ${spec.name}: +${diff.added}/-${diff.removed} lines. The file on disk now includes the formatter's changes below; base any later edit on this content.\n${diff.text}`;
    });
    return report === undefined ? undefined : { content: [...event.content, { type: 'text' as const, text: report }] };
  });
}
