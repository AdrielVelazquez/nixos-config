# fmt: off
"""Real Pi PTY and wire assertions; all inference uses loopback fake models."""
import base64
import codecs
import fcntl
import io
import json
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import pyte
from PIL import Image, ImageDraw, ImageFont

binary, entry, fixture, output, keybindings = sys.argv[1:]
root = Path(tempfile.mkdtemp(prefix='pi-role-pty-'))
agent, cwd = root / 'agent', root / 'project'
agent.mkdir(); cwd.mkdir()
out = Path(output); out.mkdir(parents=True, exist_ok=True)
settings = root / 'managed-settings.json'
settings.write_text(json.dumps({'defaultProvider': 'roles', 'defaultModel': 'auto', 'defaultThinkingLevel': 'high',
    'retry': {'enabled': True, 'maxRetries': 2, 'baseDelayMs': 20, 'provider': {'maxRetries': 0}},
    'compaction': {'enabled': False}, 'extensions': [entry], 'quietStartup': True}))
os.symlink(settings, agent / 'settings.json')
(agent / 'keybindings.json').write_text(Path(keybindings).read_text())
requests, failed = [], False
class Model(BaseHTTPRequestHandler):
    def log_message(self, *_args): pass
    def do_POST(self):
        global failed
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        requests.append(body)
        if body['model'] == 'primary' and 'RETRY_PROBE' in json.dumps(body['messages']) and not failed:
            failed = True
            self.send_response(429); self.send_header('Content-Type', 'application/json'); self.end_headers()
            self.wfile.write(b'{"error":{"message":"429 rate limit scripted"}}'); return
        def chunk(delta, reason=None):
            return {'id': 'roles', 'object': 'chat.completion.chunk', 'created': 1, 'model': body['model'],
                'choices': [{'index': 0, 'delta': delta, 'finish_reason': reason}]}
        self.send_response(200); self.send_header('Content-Type', 'text/event-stream'); self.end_headers()
        for event in [chunk({'role': 'assistant', 'content': f'ROLE_REPLY_{len(requests)}'}), chunk({}, 'stop')]:
            self.wfile.write(('data: ' + json.dumps(event) + '\n\n').encode())
        self.wfile.write(b'data: [DONE]\n\n'); self.wfile.flush()
server = ThreadingHTTPServer(('127.0.0.1', 0), Model)
thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
image = io.BytesIO(); Image.new('RGB', (4, 4), '#00ff88').save(image, format='PNG')
events = root / 'events.jsonl'
env = {key: os.environ[key] for key in ['PATH', 'SHELL'] if key in os.environ}
env.update(HOME=str(root), TMPDIR=str(root), XDG_CONFIG_HOME=str(root / 'config'), XDG_CACHE_HOME=str(root / 'cache'),
    PI_CODING_AGENT_DIR=str(agent), PI_OFFLINE='1', PI_TELEMETRY='0', USER='fixture', TERM='xterm-256color',
    COLORTERM='truecolor', LANG='C.UTF-8', PI_ROLE_EVENTS=str(events), PI_ROLE_IMAGE=base64.b64encode(image.getvalue()).decode(),
    PI_ROLE_BASE_URL=f'http://127.0.0.1:{server.server_port}/v1')
args = [binary, '--offline', '--no-approve', '--no-context-files', '--no-skills', '--no-prompt-templates', '--no-mcp',
    '--tui-mode', 'fullscreen', '-e', fixture, '--smol', 'fixture/small:off']
pid, master = pty.fork()
if pid == 0: os.chdir(cwd); os.execve(binary, args, env)
rows = 38
screen = pyte.Screen(120, rows); stream = pyte.Stream(screen)
decoder = codecs.getincrementaldecoder('utf8')('replace'); raw = bytearray(); exited = None

def records():
    return [json.loads(line) for line in events.read_text().splitlines()] if events.exists() else []
def visible(): return '\n'.join(screen.display)
def pump():
    global exited
    if select.select([master], [], [], .04)[0]:
        try:
            data = os.read(master, 65536); raw.extend(data); stream.feed(decoder.decode(data))
        except OSError: pass
    if exited is None:
        done, status = os.waitpid(pid, os.WNOHANG)
        if done: exited = os.waitstatus_to_exitcode(status)
def wait(predicate, label):
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        pump()
        if predicate(): return
        assert exited is None, f'Pi exited {exited}: {label}\n{visible()}'
    raise AssertionError(f'{label}\n{visible()}')
def idle(duration=.3):
    deadline = time.monotonic() + duration
    while time.monotonic() < deadline: pump()
def send(text): os.write(master, text.encode())
def resize(width):
    fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack('HHHH', rows, width, 0, 0))
    screen.resize(rows, width); os.kill(pid, signal.SIGWINCH); idle()
def turn(text, expected):
    before = sum(r.get('settled', False) for r in records()); start = len(requests)
    send(text + '\r'); wait(lambda: sum(r.get('settled', False) for r in records()) > before, text)
    actual = [r['model'] for r in requests[start:]]
    assert actual == expected, f'{text}: {actual} != {expected}\n{visible()}'
    idle(.1)
def screenshot(name):
    (out / f'{name}.txt').write_text(visible())
    if not os.environ.get('PI_UI_FONT'): return
    font = ImageFont.truetype(os.environ['PI_UI_FONT'], 14); width = round(font.getlength('M')); height = 18
    image = Image.new('RGB', (screen.columns * width, rows * height), '#090b10'); draw = ImageDraw.Draw(image)
    for y, line in enumerate(screen.display): draw.text((0, y * height), line, font=font, fill='#dddddd')
    image.save(out / f'{name}.png')
try:
    resize(120); wait(lambda: any(r.get('startup') for r in records()), 'startup'); idle()
    turn('DEFAULT_PROBE', ['primary'])
    for _ in range(5): send('\x14'); idle(.05)
    turn('THINKING_PROBE', ['primary'])
    assert requests[-1].get('reasoning_effort') == 'low', requests[-1]
    send('\x1b[Z'); idle(); turn('SHIFT_TAB_PLAN_PROBE', ['strong'])
    assert requests[-1].get('reasoning_effort') == 'high', requests[-1]
    send('\x1b[Z'); idle(); turn('SHIFT_TAB_BUILD_PROBE', ['primary'])
    assert requests[-1].get('reasoning_effort') == 'high', requests[-1]
    turn('/plan PLAN_PROBE', ['strong']); turn('/build BUILD_PROBE', ['primary'])
    send('/use-role smol\r'); idle(); turn('FLAG_PROBE', ['small'])
    send('/build\r'); idle()
    send('/models\r'); wait(lambda: 'Chat roles' in visible() and 'DEFAULT' in visible(), 'models wide')
    screenshot('models-120'); assert all(len(line) == 120 for line in screen.display)
    resize(80); wait(lambda: 'DEFAULT' in visible() and 'New role' in visible(), 'models narrow'); screenshot('models-80')
    send('\r'); wait(lambda: 'Model for default' in visible(), 'model picker')
    send('\x1b[B\r'); wait(lambda: 'Thinking level' in visible(), 'thinking picker')
    send('\r'); overlay = agent / 'model-roles.user.json'
    wait(lambda: overlay.exists() and json.loads(overlay.read_text()).get('modelRoles', {}).get('default') == 'fixture/small:off', 'overlay persisted')
    assert overlay.stat().st_mode & 0o777 == 0o600
    wait(lambda: 'Chat roles' in visible(), 'models returns'); send('\x1b'); idle()
    for count in [2, 3]:
        send('/reload\r'); wait(lambda: sum(r.get('startup', False) for r in records()) == count, 'reload'); idle()
    turn('PERSISTED_PROBE', ['small'])
    send('/role default fixture/primary:high\r'); idle()
    turn('RETRY_PROBE', ['primary', 'small'])
    turn('COOLDOWN_PROBE', ['small']); idle(2.1); turn('RESTORE_PROBE', ['primary'])
    send('/new\r'); idle(); turn('/fixture-image', ['strong'])
    assert any(p.get('type') == 'image_url' for m in requests[-1]['messages'] if isinstance(m.get('content'), list) for p in m['content'])
    send('/quit\r'); wait(lambda: exited is not None, 'quit'); assert exited == 0
    assert (agent / 'settings.json').is_symlink() and settings.read_bytes() == (agent / 'settings.json').read_bytes()
    for error in ['Extension error', 'Failed to load extension', 'Unhandled']: assert error not in raw.decode('utf8', 'replace'), error
    # Headless uses the same real extension and local provider, no TUI-specific access.
    run = subprocess.run([binary, '--offline', '--no-approve', '--no-context-files', '--no-skills', '--no-prompt-templates', '--no-mcp',
        '-e', fixture, '--mode', 'json', '-p', 'HEADLESS_PROBE'], env=env, cwd=cwd, capture_output=True, text=True, timeout=30)
    assert run.returncode == 0 and run.stderr == '', run.stderr
    assert requests[-1]['model'] == 'primary'
    print('PASS: real Pi roles routing, soft plan/build, CLI override, /models 120/80 edit persistence, reload twice, 429/cooldown/restore, image routing, headless stderr clean')
finally:
    (out / 'requests.json').write_text(json.dumps(requests, indent=2)); (out / 'raw.ansi').write_bytes(raw)
    if exited is None:
        try: os.killpg(pid, signal.SIGTERM); os.waitpid(pid, 0)
        except (ProcessLookupError, ChildProcessError): pass
    os.close(master); server.shutdown(); server.server_close(); thread.join(timeout=2)
