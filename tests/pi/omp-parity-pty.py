"""Real generated combined Pi configuration, native PTY and loopback-only inference."""
import codecs
import fcntl
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import threading
import time
import pyte
from PIL import Image, ImageDraw, ImageFont

binary, spec_file, fixture, output = sys.argv[1:]
assert os.environ.get('NIX_BUILD_TOP'), 'combined PTY must run in the sandbox'
spec = json.loads(Path(spec_file).read_text())
assert all(spec['enabled'].values()), spec['enabled']
root = Path(os.environ['TMPDIR']) / 'omp-parity'
agent, cwd = root / 'agent', root / 'project'
agent.mkdir(parents=True); cwd.mkdir()
(cwd / 'main.ts').write_text('export const value = 1;\n')
(cwd / 'tsconfig.json').write_text('{"compilerOptions":{"strict":true,"noEmit":true},"include":["main.ts"]}')
files = dict(spec['files'], **{'settings.json': spec['settingsFile']})
for name, source in files.items():
    target = agent / name; target.parent.mkdir(parents=True, exist_ok=True); target.symlink_to(source)
managed = {name: Path(source).read_bytes() for name, source in files.items()}
out = Path(output); out.mkdir()
# Preserve the generated managed files for an independently rendered lab capture.
for name, source in files.items():
    target = out / 'agent' / name; target.parent.mkdir(parents=True, exist_ok=True); target.symlink_to(source)
events = root / 'events.jsonl'
requests = []
class Provider(BaseHTTPRequestHandler):
    def log_message(self, *_args): pass
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        requests.append(body)
        primary = [request for request in requests if request['model'] == 'primary']
        headless = 'HEADLESS_PARITY' in json.dumps(body['messages'])
        edit = body['model'] == 'primary' and len(primary) == 1 and not headless
        if edit:
            delta = {'role': 'assistant', 'tool_calls': [{'index': 0, 'id': 'parity-edit', 'type': 'function', 'function': {
                'name': 'edit', 'arguments': json.dumps({'path': 'main.ts', 'oldText': 'export const value = 1;', 'newText': 'export const value = 2;'})}}]}
        else:
            text = 'Combined UI session' if body['model'] == 'tiny' else 'HEADLESS_PARITY_COMPLETE' if headless else (
                'PARITY_ASSISTANT_COMPLETE\n\nUpdated the TypeScript value with native edit execution. '
                'The managed omp prompt, LSP diagnostics, structural search and inline word completion remain active.')
            delta = {'role': 'assistant', 'content': text}
        def chunk(value, reason=None):
            return {'id': 'parity', 'object': 'chat.completion.chunk', 'created': 1, 'model': body['model'],
                    'choices': [{'index': 0, 'delta': value, 'finish_reason': reason}]}
        self.send_response(200); self.send_header('Content-Type', 'text/event-stream'); self.end_headers()
        for item in [chunk(delta), chunk({}, 'tool_calls' if edit else 'stop')]:
            self.wfile.write(('data: ' + json.dumps(item) + '\n\n').encode())
        self.wfile.write(b'data: [DONE]\n\n'); self.wfile.flush()
server = ThreadingHTTPServer(('127.0.0.1', 0), Provider)
thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
env = {key: os.environ[key] for key in ['PATH', 'SHELL'] if key in os.environ}
env.update(HOME=str(root), TMPDIR=str(root), XDG_CONFIG_HOME=str(root / 'config'), XDG_CACHE_HOME=str(root / 'cache'),
           XDG_STATE_HOME=str(root / 'state'), PI_CODING_AGENT_DIR=str(agent), PI_OFFLINE='1', PI_TELEMETRY='0',
           USER='fixture', TERM='xterm-256color', COLORTERM='truecolor', LANG='C.UTF-8',
           PI_PARITY_EVENTS=str(events), PI_PARITY_BASE_URL=f'http://127.0.0.1:{server.server_port}/v1')
args = [binary, '--offline', '--no-approve', '--no-context-files', '--no-skills', '--no-prompt-templates', '--no-mcp',
        '--tui-mode', 'fullscreen', '-e', fixture]
pid, master = pty.fork()
if pid == 0: os.chdir(cwd); os.execve(binary, args, env)
rows = 44
screen = pyte.Screen(120, rows); stream = pyte.Stream(screen)
decoder = codecs.getincrementaldecoder('utf8')('replace'); raw = bytearray(); exited = None
results = []
def records():
    return [json.loads(line) for line in events.read_text().splitlines()] if events.exists() else []
def visible(): return '\n'.join(screen.display)
def plain(value): return re.sub(r'\x1b\[[0-9;]*m', '', re.sub(r'\x1b_[^\x07]*\x07', '', value))
def pump():
    global exited
    if select.select([master], [], [], .05)[0]:
        try:
            data = os.read(master, 65536); raw.extend(data); stream.feed(decoder.decode(data))
        except OSError: pass
    if exited is None:
        done, status = os.waitpid(pid, os.WNOHANG)
        if done: exited = os.waitstatus_to_exitcode(status)
def wait(predicate, label, timeout=25):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        pump()
        if predicate(): return
        assert exited is None, f'Pi exited {exited}: {label}\n{visible()}'
    raise AssertionError(f'{label}\n{visible()}')
def idle(duration=.3):
    deadline = time.monotonic() + duration
    while time.monotonic() < deadline: pump()
def send(value): os.write(master, value if isinstance(value, bytes) else value.encode())
def draft(text):
    send(b'\x1bz'); idle(.1)
    send(b'\x1b[200~' + text.encode() + b'\x1b[201~'); idle()
def capture():
    count = sum('buffer' in item for item in records()); send(b'\x1bg')
    wait(lambda: sum('buffer' in item for item in records()) > count, 'real combined editor witness')
    value = [item for item in records() if 'buffer' in item][-1]
    assert all(width <= value['width'] for width in value['widths']), value
    assert not any(item.get('overflow') for item in records()), 'combined editor overflowed'
    return value
def ghost():
    draft('configurat'); value = capture()
    assert value['buffer'] == 'configurat', value
    rendered = '\n'.join(value['lines'])
    assert 'configuration' in plain(rendered), value
    assert re.search(r'configurat\x1b_pi:c\x07.*?i', rendered), value
    line = next(line for line in map(plain, value['lines']) if 'configuration' in line)
    assert line.startswith('│') and line.rstrip().endswith('│'), line
    wait(lambda: 'configuration' in visible(), 'ghost suffix inside real omp editor')
    send('\t'); idle()
    assert capture()['buffer'] == 'configuration '
def resize(width):
    fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack('HHHH', rows, width, 0, 0))
    screen.resize(rows, width); os.kill(pid, signal.SIGWINCH); idle()
def frame_count():
    return sum(line.strip().startswith('╭') and set(line.strip()) <= set('╭─╮') for line in screen.display)
def status_rows(): return [line for line in screen.display if 'π' in line and '›' in line]
def statuses(label):
    wait(lambda: 'ast-grep RO' in visible() and 'LSP ' in visible() and ('role: default' in visible() or re.search(r'(default|tiny) → fixture/(primary|tiny)', visible())), label)
    assert frame_count() == 1, visible()
    assert len(status_rows()) == 1, visible()
def clean_errors():
    text = raw.decode('utf8', 'replace')
    for error in ['Extension error', 'Failed to load extension', 'stale after', 'TypeError:', 'Unhandled']:
        assert error not in text, error

def screenshot(name):
    font = ImageFont.truetype(os.environ['PI_UI_FONT'], 16)
    cell_w, cell_h = round(font.getlength('M')), 21
    image = Image.new('RGB', (screen.columns * cell_w + 32, rows * cell_h + 32), '#000000')
    draw = ImageDraw.Draw(image)
    ansi = {'black': '#351b0e', 'red': '#9b291c', 'green': '#636232', 'brown': '#c36e28',
            'blue': '#515c5d', 'magenta': '#9b1d29', 'cyan': '#588056', 'white': '#f7d75c'}
    def color(value, fallback):
        if len(value) == 6 and all(char in '0123456789abcdefABCDEF' for char in value): return '#' + value
        return ansi.get(value, fallback)
    for y in range(rows):
        for x in range(screen.columns):
            cell = screen.buffer[y][x]; px, py = 16 + x * cell_w, 16 + y * cell_h
            foreground, background = color(cell.fg, '#f7d66a'), color(cell.bg, '#000000')
            if cell.reverse: foreground, background = background, foreground
            draw.rectangle((px, py, px + cell_w, py + cell_h), fill=background)
            draw.text((px, py), cell.data, font=font, fill=foreground)
    image.save(out / name)
    (out / name.replace('.png', '.txt')).write_text(visible())

try:
    resize(120)
    wait(lambda: any(item.get('startup') for item in records()), 'combined startup')
    wait(lambda: frame_count() == 1 and len(status_rows()) == 1, 'omp powerline row and rounded prompt')
    assert next(item for item in records() if item.get('startup'))['theme'] == 'omp-reference'
    clean_errors(); results.append('1: real omp startup and clean extension output')
    statuses('three real extension statuses at 120 columns'); screenshot('startup-120.png')
    resize(80); statuses('three real extension statuses at 80 columns'); screenshot('startup-80.png')
    resize(120); results.append('2: real AST/LSP/model-role statuses at 120 and 80 columns')
    assert requests == [], requests
    ghost()
    for text in ['/mo', '@src/', '```\nconfigurat']:
        draft(text); value = capture()
        assert value['buffer'] == text, value
        assert 'configuration' not in plain('\n'.join(value['lines'])), value
    assert requests == [], requests
    results.append('3: cold dictionary suffix inside omp editor, Tab buffer acceptance, command/path/fence gates')
    draft('PARITY_USER_TURN update the TypeScript value')
    assert capture()['model'] == 'roles/auto', 'normal user turn must enter the virtual role model'
    send('\r')
    wait(lambda: any(item.get('settled') for item in records()), 'combined edit/model turn', 60)
    wait(lambda: 'PARITY_ASSISTANT_COMPLETE' in visible() and 'Edit: main.ts' in visible(), 'assistant and omp edit card')
    assert (cwd / 'main.ts').read_text() == 'export const value = 2;\n'
    primary = [request for request in requests if request['model'] != 'tiny']
    assert [request['model'] for request in primary] == ['primary', 'primary'], [request['model'] for request in requests]
    tools = {tool['function']['name'] for tool in primary[0]['tools']}
    for tool in ['lsp_diagnostics', 'lsp_hover', 'lsp_goto_definition', 'ast_grep_run', 'ast_grep_scan']:
        assert tool in tools, (tool, sorted(tools))
    assert any(item.get('tool') == 'edit' for item in records()), records()
    statuses('three statuses after LSP starts at 120 columns')
    resize(80); statuses('three statuses after LSP starts at 80 columns'); screenshot('conversation-80.png'); resize(120)
    results.append('4: roles/auto -> primary, real edit card and assistant, LSP/AST wire tool definitions')
    draft('/models'); send('\r')
    wait(lambda: 'DEFAULT' in visible() and 'fixture/primary' in visible() and 'Chat roles' in visible(), 'combined /models screen')
    screenshot('models-120.png'); send(b'\x1b'); idle()
    wait(lambda: frame_count() == 1, 'editor returns after models overlay')
    ghost(); results.append('5: /models DEFAULT selector and working ghost editor after Esc')
    draft('configurat'); capture(); screenshot('final.png')
    for count in [2, 3]:
        draft('/reload'); send('\r')
        wait(lambda: sum(item.get('startup', False) for item in records()) == count, 'combined reload')
        statuses(f'one editor/primary row and statuses after reload {count - 1}')
        ghost(); clean_errors()
    draft('/new'); send('\r')
    wait(lambda: sum(item.get('startup', False) for item in records()) == 4, 'combined new session')
    statuses('one editor/primary row and statuses after new')
    ghost(); clean_errors()
    results.append('6: two reloads/new preserve one frame/primary status row, completion and clean output')
    draft('/quit'); send('\r'); wait(lambda: exited is not None, 'clean quit'); assert exited == 0
    headless = [arg for arg in args if arg not in ['--tui-mode', 'fullscreen']]
    for mode in [[], ['--mode', 'json']]:
        start = len(requests)
        result = subprocess.run(headless + mode + ['-p', 'HEADLESS_PARITY'], cwd=cwd, env=env, capture_output=True, timeout=60)
        assert result.returncode == 0 and result.stderr == b'', (result.returncode, result.stderr.decode())
        assert b'HEADLESS_PARITY_COMPLETE' in result.stdout, result.stdout.decode()
        chat_models = [request['model'] for request in requests[start:] if request['model'] != 'tiny']
        assert chat_models == ['primary'], chat_models
    results.append('7: same generated settings print/JSON exit zero with empty stderr')
    for name, expected in managed.items():
        assert (agent / name).is_symlink() and (agent / name).read_bytes() == expected, name
    clean_errors(); results.append('8: all managed symlinks and exact bytes preserved')
    print('\n'.join('PASS ' + result for result in results))
finally:
    (out / 'raw.ansi').write_bytes(raw)
    (out / 'events.json').write_text(json.dumps(records(), indent=2))
    (out / 'requests.json').write_text(json.dumps(requests, indent=2))
    (out / 'assertions.json').write_text(json.dumps(results, indent=2))
    if exited is None:
        try: os.killpg(pid, signal.SIGTERM); os.waitpid(pid, 0)
        except (ProcessLookupError, ChildProcessError): pass
    os.close(master); server.shutdown(); server.server_close(); thread.join(timeout=2)
