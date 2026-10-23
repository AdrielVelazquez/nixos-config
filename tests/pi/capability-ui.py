"""Actual Pi fullscreen PTY, generated Tuios hook and immutable module config."""
import codecs
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import sys
import termios
import time
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import pyte
from PIL import Image, ImageDraw, ImageFont

binary, spec_file, fixture, hook, tuios, question, output = sys.argv[1:]
assert os.environ.get('NIX_BUILD_TOP'), 'PTY belongs in a Nix sandbox'
spec = json.loads(Path(spec_file).read_text())
root = Path(os.environ['TMPDIR']) / 'ui'
agent, cwd = root / 'agent', root / 'project'
agent.mkdir(parents=True); cwd.mkdir()
(cwd / 'visual-canary.ts').write_text('export const value = 1;\n')
files = dict(spec['files'], **{'settings.json': spec['settingsFile']})
for name, source in files.items(): os.symlink(source, agent / name)
events_file, tuios_file = root / 'events.jsonl', root / 'tuios.jsonl'
out = Path(output); out.mkdir()
generated = out / 'agent'; generated.mkdir()
for name, source in files.items(): os.symlink(source, generated / name)
requests = []
class Model(BaseHTTPRequestHandler):
    def log_message(self, *_args): pass
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        requests.append(body)
        count = len(requests)
        tool = None
        if count == 1: tool = ('read', {'path': 'visual-canary.ts'})
        elif count == 2: tool = ('edit', {'path': 'visual-canary.ts', 'oldText': 'export const value = 1;', 'newText': 'export const value = 2;'})
        elif count == 4: tool = ('question', {'questions': [{'header': 'UI', 'question': 'NATIVE_TOOL_QUESTION', 'options': [{'label': 'Accept', 'description': 'fixture'}, {'label': 'Decline', 'description': 'fixture'}]}]})
        def chunk(delta, reason=None):
            return {'id': 'ui-fixture', 'object': 'chat.completion.chunk', 'created': 1, 'model': 'unit',
                    'choices': [{'index': 0, 'delta': delta, 'finish_reason': reason}]}
        if tool:
            data = [chunk({'role': 'assistant', 'tool_calls': [{'index': 0, 'id': f'ui-{count}', 'type': 'function', 'function': {'name': tool[0], 'arguments': json.dumps(tool[1])}}]}), chunk({}, 'tool_calls')]
        else:
            text = 'VISUAL_TURN_COMPLETE' if count == 3 else 'VISUAL_QUESTION_COMPLETE' if count == 5 else 'VISUAL_RELOAD_COMPLETE'
            data = [chunk({'role': 'assistant', 'content': text}), chunk({}, 'stop')]
        self.send_response(200); self.send_header('Content-Type', 'text/event-stream'); self.end_headers()
        for item in data: self.wfile.write(('data: ' + json.dumps(item) + '\n\n').encode())
        self.wfile.write(b'data: [DONE]\n\n'); self.wfile.flush()
server = ThreadingHTTPServer(('127.0.0.1', 0), Model)
thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
env = {key: os.environ[key] for key in ['PATH', 'SHELL'] if key in os.environ}
env.update(HOME=str(root), TMPDIR=str(root), XDG_CONFIG_HOME=str(root / 'config'), XDG_CACHE_HOME=str(root / 'cache'),
           PI_CODING_AGENT_DIR=str(agent), PI_OFFLINE='1', PI_TELEMETRY='0', USER='fixture',
           TERM='xterm-256color', COLORTERM='truecolor', LANG='C.UTF-8', TUIOS_ENV='1',
           PI_UI_EVENTS=str(events_file), PI_TUIOS_EVENTS=str(tuios_file), PI_TUIOS_BINARY=tuios,
           PI_UI_BASE_URL=f'http://127.0.0.1:{server.server_port}/v1')
args = [binary, '--offline', '--no-approve', '--no-context-files', '--no-skills', '--no-prompt-templates',
        '--no-mcp', '--tui-mode', 'fullscreen', '--model', 'fixture/unit', '-e', fixture, '-e', hook, '-e', question]
pid, master = pty.fork()
if pid == 0: os.chdir(cwd); os.execve(binary, args, env)
rows = 44
screen = pyte.Screen(120, rows); stream = pyte.Stream(screen)
decoder = codecs.getincrementaldecoder('utf8')('replace')
raw = bytearray(); exited = None
def records(file=events_file):
    try: return [json.loads(line) for line in file.read_text().splitlines()]
    except FileNotFoundError: return []
def visible(): return '\n'.join(screen.display)
def prompt_frames(): return sum(line.strip().startswith('╭') and set(line.strip()) <= set('╭─╮') for line in screen.display)
def pump():
    global exited
    if select.select([master], [], [], .08)[0]:
        try:
            data = os.read(master, 65536); raw.extend(data); stream.feed(decoder.decode(data))
        except OSError: pass
    if exited is None:
        done, status = os.waitpid(pid, os.WNOHANG)
        if done: exited = os.waitstatus_to_exitcode(status)
def wait(predicate, label):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        pump()
        if predicate(): return
        assert exited is None, f'Pi exited {exited}: {label}'
    raise AssertionError(f'{label}\n{visible()}')
def send(data): os.write(master, data if isinstance(data, bytes) else data.encode())
def resize(width):
    fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack('HHHH', rows, width, 0, 0))
    screen.resize(rows, width); os.kill(pid, signal.SIGWINCH)
    for _ in range(5): pump()
def screenshot(name):
    font = ImageFont.truetype(os.environ['PI_UI_FONT'], 16)
    cell_w, cell_h = round(font.getlength('M')), 21
    image = Image.new('RGB', (screen.columns * cell_w + 32, screen.lines * cell_h + 32), '#090b10')
    draw = ImageDraw.Draw(image)
    def color(value, fallback):
        return '#' + value if len(value) == 6 and all(c in '0123456789abcdefABCDEF' for c in value) else fallback
    for y in range(screen.lines):
        for x in range(screen.columns):
            cell = screen.buffer[y][x]
            px, py = 16 + x * cell_w, 16 + y * cell_h
            draw.rectangle((px, py, px + cell_w, py + cell_h), fill=color(cell.bg, '#090b10'))
            draw.text((px, py), cell.data, font=font, fill=color(cell.fg, '#e2e8f0'))
    image.save(out / name)
try:
    resize(120)
    wait(lambda: any(r.get('startup') for r in records()), 'startup')
    wait(lambda: 'unit' in visible() and '0%' in visible(), 'omp primary model/context status row')
    wait(lambda: prompt_frames() == 1, 'rounded omp prompt')
    wait(lambda: all(status in visible() for status in ['ast-grep RO', 'LSP 2 configured', 'roles default']), 'three compact footer statuses')
    assert next(r['theme'] for r in records() if r.get('startup')) == 'omp-reference'
    for tool in next(r['nativeTools'] for r in records() if r.get('startup')):
        assert tool['source']['source'] == 'builtin' and tool['source']['path'] == 'builtin:' + tool['name'], tool
    (out / 'wide.txt').write_text(visible())
    screenshot('startup.png')
    resize(80)
    wait(lambda: all(status in visible() for status in ['ast-grep RO', 'LSP 2 configured', 'roles default']), 'three footer statuses at 80 columns')
    assert prompt_frames() == 1
    (out / '80-columns.txt').write_text(visible()); screenshot('80-columns.png')
    resize(120)
    send('VISUAL_USER_PROMPT\r')
    wait(lambda: 'VISUAL_TURN_COMPLETE' in visible(), 'real streamed agent turn')
    wait(lambda: any(r.get('settled') for r in records()), 'settled turn')
    assert (cwd / 'visual-canary.ts').read_text() == 'export const value = 2;\n'
    assert {'read', 'edit'}.issubset({r.get('tool') for r in records()})
    assert 'Read 1 file' in visible() and 'Edit: visual-canary.ts' in visible(), visible()
    assert 'export const value = 1;' in visible() and 'export const value = 2;' in visible(), visible()
    assert 'VISUAL_USER_PROMPT' in visible(), visible()
    (out / 'conversation.txt').write_text(visible()); screenshot('conversation.png')
    send('/set-thinking high\r')
    wait(lambda: 'high' in visible(), 'status reflects native thinking-level selection while idle')
    send('/capture '); send(b'\x1b[200~' + 'α e\u0301 hello 世界 👋'.encode() + b'\x1b[201~')
    resize(40); send('\r')
    wait(lambda: any(r.get('capture') == 'α e\u0301 hello 世界 👋' for r in records()), '40-column Unicode/CJK/emoji paste')
    resize(40); (out / 'narrow.txt').write_text(visible()); resize(120)
    send('/dialog\r'); wait(lambda: 'NATIVE_QUESTION' in visible(), 'question'); send('\r')
    wait(lambda: any('answer' in r for r in records()), 'answer')
    send('/dialog\r'); wait(lambda: sum(r.get('event') == 'start' for r in records()) == 2, 'second question'); send(b'\x1b')
    wait(lambda: sum(r.get('event') == 'end' for r in records()) == 2, 'cancel prompt end')
    # ui_prompt_end is emitted before the awaiting command handler resumes.
    wait(lambda: sum('answer' in r for r in records()) == 2, 'cancel result recorded')
    assert [r['answer'] for r in records() if 'answer' in r] == ['Yes fixture', None], records()
    wait(lambda: sum(r['payload']['hook_event_name'] == 'ui_prompt_end' for r in records(tuios_file)) == 2, 'real Tuios delivery/parse')
    prompts = [r for r in records(tuios_file) if r['payload']['hook_event_name'].startswith('ui_prompt_')]
    assert len(prompts) == 4
    for r in prompts:
        assert r['explanation']['report']['state'] == ('needs_input' if r['payload']['hook_event_name'] == 'ui_prompt_start' else ('working' if r['payload'].get('busy') else 'idle')), r
    send('/capture abcdef')
    wait(lambda: '/capture abcdef' in visible(), 'mouse draft')
    row, line = next((i, line) for i, line in enumerate(screen.display) if '/capture abcdef' in line)
    column = line.index('abcdef') + 3
    send(f'\x1b[<0;{column+1};{row+1}M\x1b[<0;{column+1};{row+1}m')
    for _ in range(3): pump()
    send('X\r'); wait(lambda: sum('capture' in r for r in records()) == 2, 'mouse submission')
    assert [r['capture'] for r in records() if 'capture' in r][-1] == 'abcXdef'
    send('VISUAL_QUESTION_PROMPT\r'); wait(lambda: 'NATIVE_TOOL_QUESTION' in visible(), 'actual question tool')
    send(b'\x1b[B\x1b[B\r')
    wait(lambda: sum(r.get('kind') == 'input' and r.get('event') == 'start' for r in records()) == 1, 'free-form question input')
    send('free-form canary\r')
    wait(lambda: 'VISUAL_QUESTION_COMPLETE' in visible(), 'question tool resumed inference')
    wait(lambda: any(r.get('tool') == 'question' for r in records()), 'question result')
    assert 'free-form canary' in json.dumps(next(r['details'] for r in records() if r.get('tool') == 'question'))
    for count in [2, 3]:
        send('/reload\r'); wait(lambda: sum(r.get('startup', False) for r in records()) == count, 'reload')
        wait(lambda: 'roles default' in visible() and 'LSP 2 configured' in visible(), 'status after reload')
        wait(lambda: prompt_frames() == 1, 'single rounded editor owner')
    send('VISUAL_AFTER_RELOAD\r'); wait(lambda: 'VISUAL_RELOAD_COMPLETE' in visible(), 'streaming after reload')
    assert len(requests) == 6, len(requests)
    send('/new\r'); wait(lambda: 'VISUAL_AFTER_RELOAD' not in visible(), 'new session clears transcript')
    wait(lambda: prompt_frames() == 1, 'single editor after new session')
    send('/quit\r'); wait(lambda: exited is not None, 'quit'); assert exited == 0
    text = raw.decode('utf8', errors='replace')
    for error in ['Extension error', 'Failed to load extension', 'stale after']: assert error not in text
    # Run both non-TUI frontends with the same generated symlinked settings.
    headless = [arg for arg in args if arg not in ['--tui-mode', 'fullscreen']]
    for mode in [[], ['--mode', 'json']]:
        result = subprocess.run(headless + mode + ['-p', 'headless smoke'], cwd=cwd, env=env, capture_output=True, timeout=20)
        assert result.returncode == 0, result.stderr.decode()
        assert result.stderr == b'', result.stderr.decode()
        assert b'VISUAL_RELOAD_COMPLETE' in result.stdout, result.stdout.decode()
    rpc = subprocess.run(headless + ['--mode', 'rpc'], input=b'{"type":"get_state"}\n', cwd=cwd, env=env, capture_output=True, timeout=20)
    assert rpc.returncode == 0 and rpc.stderr == b'', rpc.stderr.decode()
    assert b'extension_error' not in rpc.stdout, rpc.stdout.decode()
    for name, source in files.items():
        assert (agent / name).is_symlink(), name
        assert (agent / name).read_bytes() == Path(source).read_bytes(), name
    print('PASS: omp theme/model/context/rounded prompt, three statuses at 120/80, real read/edit/question/Tuios, Unicode/CJK/emoji/mouse/40-column resize, two reloads/new, immutable symlinks, clean print/JSON/RPC stderr')
finally:
    (out / 'raw.ansi').write_bytes(raw)
    (out / 'events.json').write_text(json.dumps(records(), indent=2))
    (out / 'tuios-events.json').write_text(json.dumps(records(tuios_file), indent=2))
    (out / 'requests.json').write_text(json.dumps(requests, indent=2))
    if exited is None:
        try: os.killpg(pid, signal.SIGTERM); os.waitpid(pid, 0)
        except (ProcessLookupError, ChildProcessError): pass
    os.close(master)
    server.shutdown(); server.server_close(); thread.join(timeout=2)
