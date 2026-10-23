import { appendFileSync } from 'node:fs';
export default function (pi) {
  pi.registerProvider('fixture', { baseUrl: process.env.PI_ROLE_BASE_URL, apiKey: 'synthetic-only', api: 'openai-completions', models: ['primary', 'small', 'strong'].map(id => ({
    id, name: id, reasoning: true, input: id === 'strong' ? ['text', 'image'] : ['text'], contextWindow: 200000, maxTokens: 8192,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
  })) });
  const record = data => appendFileSync(process.env.PI_ROLE_EVENTS, JSON.stringify(data) + '\n');
  pi.on('session_start', () => record({ startup: true }));
  pi.on('agent_settled', () => record({ settled: true }));
  pi.registerCommand('fixture-image', { description: 'Send synthetic image through real Pi', handler: () => {
    pi.sendUserMessage([{ type: 'text', text: 'IMAGE_PROBE' }, { type: 'image', data: process.env.PI_ROLE_IMAGE, mimeType: 'image/png' }]);
  } });
}
