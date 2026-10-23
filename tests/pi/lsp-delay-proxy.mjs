// Test transport: delay the REAL server's diagnostic frames, never synthesize them.
import { spawn } from 'node:child_process';
import { appendFileSync } from 'node:fs';
const [executable, ...args] = process.argv.slice(2);
const child = spawn(executable, args, { stdio: ['pipe', 'pipe', 'inherit'] });
let buffer = Buffer.alloc(0);
process.stdin.pipe(child.stdin);
child.stdout.on('data', chunk => {
  buffer = Buffer.concat([buffer, chunk]);
  while (true) {
    const split = buffer.indexOf('\r\n\r\n');
    if (split < 0) break;
    const size = Number(/Content-Length:\s*(\d+)/i.exec(buffer.subarray(0, split).toString())[1]);
    if (buffer.length < split + 4 + size) break;
    const frame = Buffer.from(buffer.subarray(0, split + 4 + size));
    const message = JSON.parse(buffer.subarray(split + 4, split + 4 + size));
    buffer = buffer.subarray(split + 4 + size);
    if (message.method === 'textDocument/publishDiagnostics') {
      appendFileSync(process.env.LSP_DELAY_LOG, JSON.stringify({ at: Date.now(), ...message }) + '\n');
      setTimeout(() => process.stdout.write(frame), 9000);
    } else process.stdout.write(frame);
  }
});
child.on('error', error => { console.error(error.message); process.exit(1); });
child.on('exit', code => process.exit(code ?? 1));
for (const signal of ['SIGTERM', 'SIGINT']) process.on(signal, () => child.kill(signal));
