import { appendFileSync } from 'node:fs';
import { CustomEditor } from '@earendil-works/pi-coding-agent';
import { visibleWidth, truncateToWidth } from '@earendil-works/pi-tui';

/** No visual package dependency: exercise composition with an independent owner. */
export default function (pi) {
  const record = value => appendFileSync(process.env.PI_GHOST_EVENTS, JSON.stringify(value) + '\n');
  let current, width = 80;
  pi.registerProvider('fixture', {
    baseUrl: process.env.PI_GHOST_BASE_URL, apiKey: 'synthetic-only', api: 'openai-completions',
    models: [{id:'unit',name:'unit',reasoning:false,input:['text'],contextWindow:32000,maxTokens:128,
      cost:{input:0,output:0,cacheRead:0,cacheWrite:0}}],
  });
  pi.on('session_start', (_event, ctx) => {
    if (ctx.hasUI && ctx.mode === 'tui') ctx.ui.setEditorComponent((tui,theme,keys) => {
      class VisualOwner extends CustomEditor {
        render(columns) {
          width = columns;
          const inner = super.render(Math.max(1, columns - 4));
          return ['╭' + truncateToWidth('─ VISUAL OWNER ' + '─'.repeat(columns), columns - 2) + '╮',
            ...inner.map(line => '│ ' + line + ' '.repeat(Math.max(0,columns - 4 - visibleWidth(line))) + ' │'),
            '╰' + '─'.repeat(columns - 2) + '╯'];
        }
      }
      current = new VisualOwner(tui,theme,keys);
      return current;
    });
    record({startup:true,mode:ctx.mode});
  });
  pi.registerShortcut('alt+z', {description:'Clear fixture input',handler:async ctx => ctx.ui.setEditorText('')});
  pi.registerShortcut('alt+g', {description:'Record real buffer and rendered editor',handler:async ctx => {
    const lines = current.render(width);
    record({text:ctx.ui.getEditorText(),lines,width,widths:lines.map(visibleWidth),cursor:current.getCursor()});
  }});
}
