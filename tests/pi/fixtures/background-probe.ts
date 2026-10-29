import type { ExtensionAPI } from '@earendil-works/pi-coding-agent';
import { Type } from 'typebox';

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: 'jobs_fixture',
    label: 'Jobs fixture',
    description: 'Inspect tools or start fixture jobs in the same assistant turn.',
    parameters: Type.Object({ commands: Type.Optional(Type.Array(Type.String())) }),
    async execute(_id, params, _signal, _update, ctx) {
      if (!params.commands) {
        return { content: [{ type: 'text', text: JSON.stringify(pi.getAllTools().map((tool) => tool.name)) }], details: undefined };
      }
      const content = [];
      for (const command of params.commands) {
        const outcome = await ctx.executeTool('bg_run', { command });
        if (outcome.isError) throw new Error(JSON.stringify(outcome.result.content));
        content.push(...outcome.result.content);
      }
      return { content, details: undefined };
    },
  });
}
