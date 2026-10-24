import type { CellResult, ToolAnswer } from './eval-kernel.ts';

/**
 * Which tools a cell may reach, for `reachesTools`: lets late-registering tool providers (MCP servers still
 * connecting) finish before the cell runs. `tool.name`, `tool["name"]` and `write()` name one tool; anything that
 * treats `tool` as a value (an alias, `getattr`, `dir`) can reach all of them.
 */
export function reachedTools(code: string): 'all' | string[] {
  if (/\b(?:getattr|dir|vars)\s*\(\s*tool\b/.test(code) || /\btool\b(?!\s*[.[])/.test(code) || /\btool\s*\[(?!\s*['"][^'"]+['"]\s*\])/.test(code)) return 'all';
  const names = new Set<string>();
  for (const match of code.matchAll(/\btool\s*\.\s*([A-Za-z_]\w*)/g)) names.add(match[1]);
  for (const match of code.matchAll(/\btool\s*\[\s*['"]([^'"]+)['"]\s*\]/g)) names.add(match[1]);
  if (/\bwrite\s*\(/.test(code)) names.add('write');
  return [...names];
}

type Part = { type: string; text?: string; [key: string]: unknown };

/**
 * What a cell receives from `tool.<name>(...)`: the structured value when the tool declares one, the text when the
 * result is only text, otherwise the list of parts (images stay `{ type: "image", data, mimeType }` blocks that
 * `image()` accepts). A failed call becomes a `ToolError` in the cell.
 */
export function toolAnswer(outcome: { isError: boolean; result?: { content?: Part[]; structuredContent?: unknown } }): ToolAnswer {
  const parts = outcome.result?.content ?? [];
  const text = parts.filter(part => part.type === 'text').map(part => part.text ?? '').join('\n');
  if (outcome.isError) return { ok: false, error: text || 'the tool failed' };
  if (outcome.result?.structuredContent !== undefined) return { ok: true, value: outcome.result.structuredContent };
  if (parts.every(part => part.type === 'text')) return { ok: true, value: text };
  return { ok: true, value: parts };
}

/** Lines that follow a cell's output and say how it ended, when it did not simply finish. */
export function endNotices(result: CellResult, timeoutSeconds: number | undefined, maxOutputMiB: number): string[] {
  const notices: string[] = [];
  if (result.timedOut) notices.push(`The cell timed out after ${timeoutSeconds}s and was interrupted.`);
  if (result.cancelled) notices.push('The cell was cancelled.');
  if (result.overflow) notices.push(`The cell was interrupted: it printed more than ${maxOutputMiB} MiB.`);
  if (result.died) notices.push(`The Python kernel stopped (${result.exit ?? 'exited'}); its variables are gone and the next call starts a fresh kernel.`);
  return notices;
}
