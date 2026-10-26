# fmt: off
"""Render Pi's real TUI for a scripted session and save text, ANSI and PNG captures.

Dev tool, not a check: run it outside the sandbox to look at the UI.
  python3 preview.py --pi $(command -v pi) --settings settings.json --out /tmp/ui [--ext file.ts ...] [--cols 110 --rows 40]
settings.json is a Pi settings file; extension entries and theme paths inside it are used as written.
"""
import re, sys, argparse, codecs, fcntl, json, os, pty, select, shutil, signal, struct, subprocess, tempfile, termios, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import pyte
from PIL import Image, ImageDraw, ImageFont

ap = argparse.ArgumentParser()
ap.add_argument('--pi', required=True); ap.add_argument('--settings', required=True); ap.add_argument('--out', required=True)
ap.add_argument('--ext', action='append', default=[]); ap.add_argument('--cols', type=int, default=110); ap.add_argument("--rows", type=int, default=40)
ap.add_argument('--font', default=os.environ.get('PI_UI_FONT', ''))
ap.add_argument('--narrow', type=int, default=0, help='also capture at this width')
ap.add_argument('--check', action='store_true', help='assert the OpenCode-style contract on the captures and exit non-zero on failure')
args = ap.parse_args()
here = Path(__file__).parent
out = Path(args.out); shutil.rmtree(out, ignore_errors=True); out.mkdir(parents=True)
root = Path(tempfile.mkdtemp(prefix='pi-ui-')); agent, cwd = root / 'agent', root / 'project'
agent.mkdir(); (cwd / 'src').mkdir(parents=True)
shutil.copy(args.settings, agent / 'settings.json')
(cwd / 'src/auth.ts').write_text('export function isExpired(exp: number, now: number) {\n  return exp < now;\n}\n')
subprocess.run(['git', 'init', '-q', '-b', 'feat/session-expiry'], cwd=cwd)
events = root / 'events.jsonl'

def chunk(delta, reason=None, usage=None):
    c = {'id': 'f', 'object': 'chat.completion.chunk', 'created': 1, 'model': 'claude-sonnet-4', 'choices': [{'index': 0, 'delta': delta, 'finish_reason': reason}]}
    if usage: c['usage'] = usage
    return c
def tool(n, name, a, think=None):
    d = []
    if think: d.append(chunk({'role': 'assistant', 'reasoning_content': think}))
    d.append(chunk({'role': 'assistant', 'content': a.pop('_say', None)} if '_say' in a else {'role': 'assistant'}))
    d.append(chunk({'tool_calls': [{'index': 0, 'id': f't{n}', 'type': 'function', 'function': {'name': name, 'arguments': json.dumps(a)}}]}))
    d.append(chunk({}, 'tool_calls', {'prompt_tokens': 9000 + n * 700, 'completion_tokens': 60, 'total_tokens': 9060 + n * 700}))
    return d
FINAL = """The bug was an off-by-one in the expiry check: `isExpired` used `<`, so a token whose `exp` equals `now` was still accepted.

## What changed

- `src/auth.ts`: compare with `<=` so a token expiring *right now* is rejected
- Re-ran `npm test -- auth`: **5 passed**

```ts
export function isExpired(exp: number, now: number) {
  return exp <= now;
}
```

> Worth adding a boundary test for `exp === now` so this cannot regress.

Want me to add that test next?"""
SCRIPT = {
  1: tool(1, 'read', {'path': 'src/auth.ts'}, 'The test says an expired token is accepted. Let me read the auth module first.'),
  2: tool(2, 'bash', {'command': "printf '  FAIL  src/auth.test.ts\\n  ✕ rejects expired tokens (12 ms)\\n\\n    Expected: false\\n    Received: true\\n\\nTests: 1 failed, 4 passed\\n'; exit 1"}, None),
  3: tool(3, 'edit', {'path': 'src/auth.ts', 'oldText': '  return exp < now;', 'newText': '  return exp <= now;'}, 'Boundary case: exp === now should count as expired.'),
  4: tool(4, 'bash', {'command': "printf 'Tests: 5 passed, 5 total\\n'"}, None),
  5: [chunk({'role': 'assistant', 'content': FINAL[:i]}) for i in (0,)] + [chunk({'content': FINAL}), chunk({}, 'stop', {'prompt_tokens': 12400, 'completion_tokens': 210, 'total_tokens': 12610})],
}
SCRIPT.update({
  6: tool(6, 'todo', {'op': 'init', 'items': ['write the boundary test', 'run the suite', 'update the docs']}, 'Plan the work before touching the test.'),
  7: tool(7, 'grep', {'pattern': 'isExpired', 'path': 'src'}, 'Find every caller before touching the test.'),
  8: tool(8, 'find', {'pattern': '*.ts'}),
  9: tool(9, 'ls', {'path': 'src'}),
  10: tool(10, 'write', {'path': 'src/auth.test.ts', 'content': "import { isExpired } from './auth';\n\ntest('rejects a token expiring now', () => {\n  expect(isExpired(10, 10)).toBe(true);\n});\n"}),
  11: tool(11, 'todo', {'op': 'done', 'id': 1}),
  12: tool(12, 'edit', {'path': 'src/auth.ts', 'oldText': '  return exp ?? now;', 'newText': '  return exp <= now;'}),
  13: tool(13, 'probe', {'target': 'staging'}),
  14: tool(14, 'bash', {'command': "cat > notes.go <<'E'\npackage notes\n\nfunc Add(a, b int) int { return a + b }\nE\ntest -s notes.go"}),
  15: tool(15, 'bash', {'command': 'echo hook-me'}),
  16: tool(16, 'bash', {'command': "seq 1 28 | sed 's/^/  running case /'; sleep 3; echo 'all green'"}),
  17: [chunk({'role': 'assistant', 'content': 'Added the boundary test and ran the suite; everything passes.'}), chunk({}, 'stop', {'prompt_tokens': 15200, 'completion_tokens': 40, 'total_tokens': 15240})],
})
count = [0]
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        self.rfile.read(int(self.headers['Content-Length'])); count[0] += 1
        data = SCRIPT.get(count[0], [chunk({'role': 'assistant', 'content': 'ok'}), chunk({}, 'stop', {'prompt_tokens': 100, 'completion_tokens': 2, 'total_tokens': 102})])
        if count[0] in (1, 3, 16): time.sleep(1.6)
        self.send_response(200); self.send_header('Content-Type', 'text/event-stream'); self.end_headers()
        for item in data: self.wfile.write(('data: ' + json.dumps(item) + '\n\n').encode()); self.wfile.flush(); time.sleep(.05)
        self.wfile.write(b'data: [DONE]\n\n'); self.wfile.flush()
srv = ThreadingHTTPServer(('127.0.0.1', 0), H); threading.Thread(target=srv.serve_forever, daemon=True).start()

env = {k: os.environ[k] for k in ('PATH', 'SHELL') if k in os.environ}
env.update(HOME=str(root), TMPDIR=str(root), XDG_CONFIG_HOME=str(root / 'cfg'), XDG_CACHE_HOME=str(root / 'cache'), PI_CODING_AGENT_DIR=str(agent),
           PI_OFFLINE='1', PI_TELEMETRY='0', USER='adriel', TERM='xterm-256color', COLORTERM='truecolor', LANG='C.UTF-8',
           PI_UI_EVENTS=str(events), PI_UI_BASE_URL=f'http://127.0.0.1:{srv.server_port}/v1', GIT_AUTHOR_NAME='x', GIT_AUTHOR_EMAIL='x@x')
argv = [args.pi, '--offline', '--no-approve', '--no-context-files', '--no-skills', '--no-prompt-templates', '--no-mcp', '--tui-mode', 'fullscreen',
        '--model', 'fixture/claude-sonnet-4', '-e', str(here / 'fixture.ts')] + [x for e in args.ext for x in ('-e', e)]
pid, master = pty.fork()
if pid == 0: os.chdir(cwd); os.execve(args.pi, argv, env)
def winsize(c, r): fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack('HHHH', r, c, 0, 0))
winsize(args.cols, args.rows)
screen = pyte.Screen(args.cols, args.rows); stream = pyte.Stream(screen); dec = codecs.getincrementaldecoder('utf8')('replace'); raw = bytearray()
def pump(t=.08):
    if select.select([master], [], [], t)[0]:
        try: d = os.read(master, 65536)
        except OSError: return False
        raw.extend(d); stream.feed(dec.decode(d))
    return True
def wait(pred, timeout=60, what='condition'):
    end = time.time() + timeout
    while time.time() < end:
        pump()
        if pred(): return True
    print(f'TIMEOUT after {timeout}s waiting for {what}; screen:\n' + '\n'.join(screen.display), file=sys.stderr)
    print('events:', events.read_text() if events.exists() else '(none)', file=sys.stderr)
    sys.exit(2)
def settle(sec=1.2):
    last, t0 = None, time.time()
    while time.time() - t0 < sec:
        pump(.1); cur = '\n'.join(screen.display)
        if cur != last: last, t0 = cur, time.time()
def settled_events(): 
    try: return sum('"settled"' in l for l in events.read_text().splitlines())
    except FileNotFoundError: return 0
def send(s):
    os.write(master, s.encode()); settle(.4)
def type_text(s):
    for ch in s: os.write(master, ch.encode()); pump(.01)
    settle(.4)

PAL = ['351b0e','9b291c','636232','c36e28','515c5d','9b1d29','588056','f7d75c','874228','ff4331','b4b264','ff9566','9eb2b4','ff5b6a','8acd8f','ffe598']
NAMES = ['black','red','green','brown','blue','magenta','cyan','white']
def rgb(c, default):
    if c == 'default': return default
    if c in NAMES: return PAL[NAMES.index(c)]
    if c.startswith('bright') and c[6:] in NAMES: return PAL[8 + NAMES.index(c[6:])]
    return c if len(c) == 6 else default
FG, BG = 'f7d66a', '000000'
fontdir = Path(args.font).parent if args.font else None
def load(style):
    cands = [args.font.replace('Regular', style)] if args.font else []
    for p in cands + [args.font]:
        if p and Path(p).exists(): return ImageFont.truetype(p, 15)
    return ImageFont.load_default()
fonts = {s: load(s) for s in ('Regular', 'Bold', 'Italic')}
cw = int(round(fonts['Regular'].getlength('M'))); ch_h = 21
LEAKS = {}
def snap(name, quiet=True):
    if quiet: settle(.6)
    buf = screen.buffer; lines = []; ansi = []; LEAKS[name] = []
    img = Image.new('RGB', (cw * screen.columns, ch_h * screen.lines), '#' + BG); d = ImageDraw.Draw(img)
    for y in range(screen.lines):
        row = buf[y]; lines.append(''.join(row[x].data for x in range(screen.columns)).rstrip()); a = ''; prev = None
        for x in range(screen.columns):
            c = row[x]; fg, bg = rgb(c.fg, FG), rgb(c.bg, BG)
            if c.data.strip() and c.fg == 'default' and not c.reverse: LEAKS[name].append((y, x, c.data))
            if c.reverse: fg, bg = bg, fg
            if bg != BG: d.rectangle([x * cw, y * ch_h, (x + 1) * cw, (y + 1) * ch_h], fill='#' + bg)
            if c.data.strip(): d.text((x * cw, y * ch_h + 1), c.data, font=fonts['Bold' if c.bold else 'Italic' if c.italics else 'Regular'], fill='#' + fg)
            st = (fg, bg, c.bold, c.italics)
            if st != prev:
                a += '\x1b[0m' + ('\x1b[1m' if c.bold else '') + ('\x1b[3m' if c.italics else '') + '\x1b[38;2;{};{};{}m\x1b[48;2;{};{};{}m'.format(*bytes.fromhex(fg), *bytes.fromhex(bg)); prev = st
            a += c.data
        ansi.append(a + '\x1b[0m')
    (out / f'{name}.txt').write_text('\n'.join(lines).rstrip() + '\n'); (out / f'{name}.ansi').write_text('\n'.join(ansi) + '\n'); img.save(out / f'{name}.png')

wait(lambda: events.exists(), 30, 'startup event'); settle(2.0); snap('00-startup')
if args.narrow:
    winsize(args.narrow, 24); screen.resize(24, args.narrow); os.kill(pid, signal.SIGWINCH); settle(1.5); snap('00a-startup-narrow')
    winsize(args.cols, args.rows); screen.resize(args.rows, args.cols); os.kill(pid, signal.SIGWINCH); settle(1.5)
type_text('abcdef')
home_row = next(i for i, line in enumerate(screen.display) if 'abcdef' in line)
home_col = screen.display[home_row].index('abcdef') + 3
for suffix in ('M', 'm'): os.write(master, f'\x1b[<0;{home_col + 1};{home_row + 1}{suffix}'.encode()); pump(.1)
settle(.4); type_text('X'); snap('00b-splash-click'); send('\x15')
type_text('Fix the failing auth test in src/auth.ts'); snap('01-typed')
os.write(master, b'\r'); [pump(.1) for _ in range(9)]; snap('01b-working', quiet=False); wait(lambda: settled_events() >= 1, 90, 'first turn to settle'); settle(2.0); snap('02-turn')
type_text('Yes, add the boundary test and also check that refresh tokens use the same comparison so we do not leave the same bug elsewhere'); snap('03-composing')
send('\x15'); type_text('/'); snap('05-slash'); send('\x1b'); send('\x15')
# Not send(): its settle() only returns once the spinner stops, which is after the slow command has finished.
type_text('Now add the boundary test'); os.write(master, b'\r')
wait(lambda: any('Running seq' in line for line in screen.display), 60, 'the slow command to show as the live activity'); snap('06a-running', quiet=False)
wait(lambda: settled_events() >= 2, 120, 'second turn to settle'); settle(2.0); snap('06-turn2')
type_text('thanks'); snap('07-after')
send('\x15'); type_text('I think the infrastr'); snap('08-ghost')
send('\x15'); type_text('abcdef')
click_row = next(i for i, line in enumerate(screen.display) if 'abcdef' in line)
click_col = screen.display[click_row].index('abcdef') + 3  # 0-based column of the d
for suffix in ('M', 'm'): os.write(master, f'\x1b[<0;{click_col + 1};{click_row + 1}{suffix}'.encode()); pump(.1)
settle(.4); type_text('X'); snap('11-click'); send('\x15')
if os.environ.get('PI_UI_EXTRA'):
    send('\x15'); type_text('!echo hello from the shell'); snap('09-shell-typed'); send('\r'); settle(2.0); snap('09-shell')
    type_text('/model'); send('\r'); settle(1.5); snap('10-model'); send('\x1b'); settle(.5)
if args.narrow:
    winsize(args.narrow, args.rows); screen.resize(args.rows, args.narrow); os.kill(pid, signal.SIGWINCH); settle(1.5); snap('04-narrow')
def check():
    text = lambda name: (out / f'{name}.txt').read_text()
    rows = lambda name: text(name).split('\n')
    fails = []
    def need(ok, message):
        if not ok: fails.append(message)
    start, turn, typing, slash, turn2 = rows('00-startup'), rows('02-turn'), rows('03-composing'), rows('05-slash'), rows('06-turn2')
    need(any('██▀▀▀▀██' in l for l in start), 'a new session shows the splash wordmark')
    need(any(l.startswith(' ~/project') and 'feat/session-expiry' in l for l in start), 'footer shows the project and branch')
    need(sum(l.lstrip().startswith('┃') for l in start) >= 4, 'prompt panel draws a left bar on every row')
    need(any(l.lstrip().startswith('┃') and 'Claude Sonnet 4' in l and 'fixture' in l for l in start), 'panel carries the model row')
    need(any(l.lstrip().startswith('╹▀▀▀') for l in start), 'panel ends in the half-block edge')
    home_sizes = [('00-startup', args.cols, args.rows)] + ([('00a-startup-narrow', args.narrow, 24)] if args.narrow else [])
    for name, columns, height in home_sizes:
        frame = rows(name)
        logo = next((i for i, line in enumerate(frame) if '██▀▀▀▀██' in line), -1)
        panel = [(i, line) for i, line in enumerate(frame) if line.lstrip().startswith('┃')]
        need(logo >= 0 and bool(panel), f'{name}: splash logo and prompt are visible')
        if logo < 0 or not panel: continue
        need(panel[0][0] - logo == 7, f'{name}: logo and prompt stay adjacent')
        need(abs((logo + panel[-1][0]) / 2 - height / 2) <= 3, f'{name}: splash input group is vertically centered')
        left = len(panel[0][1]) - len(panel[0][1].lstrip())
        need(left == (columns - min(80, columns - 4)) // 2, f'{name}: splash prompt is horizontally centered and constrained')
    need(any('abcXdef' in line for line in rows('00b-splash-click')), 'mouse clicks edit the centered splash prompt at the correct column')
    need(not any('╭' in l or '╰' in l for l in start + turn), 'no rounded omp frames remain')
    need(any(l.startswith('┃  Fix the failing auth test') for l in rows('01b-working')), 'user message has bar and text column')
    need(any('→ Read src/auth.ts' in l for l in turn + rows('01b-working')), 'read is an inline line')
    full = text('02-turn') + text('06-turn2') + text('01b-working')
    for needle in ('$ printf', '← Edit src/auth.ts', '▣  Claude Sonnet 4 ·', '✱ Grep "isExpired" in src (1 match)', '✱ Glob "*.ts" (1 file)', '→ List src (1 entry)', '← Write src/auth.test.ts (5 lines)', '✗ Edit src/auth.ts', 'earlier lines · ctrl+o to expand', 'probe target=staging'):
        need(needle in full, f'transcript contains {needle!r}')
    need('```' not in full, 'markdown fences are restyled as blocks')
    # Polish: the answer footer totals what the turn changed, the working row names the tool, the todo list is a panel,
    # the footer counts changed paths, and diff rows carry syntax colours.
    need('✎ 1 file +1 −1' in text('02-turn'), 'the first answer totals its one edited file')
    need('✎ 2 files +8' in text('06-turn2'), 'the second answer counts the written file and the heredoc file, and ignores the failed edit')
    active = rows('06a-running')
    activity_rows = [(i, line) for i, line in enumerate(active) if 'Running seq 1 28' in line]
    editor_bottom = max(i for i, line in enumerate(active) if line.startswith('╹▀▀▀'))
    need(len(activity_rows) == 1 and activity_rows[0][0] > editor_bottom, 'live activity appears only in the bottom footer, below the editor')
    need(bool(activity_rows) and '▰' in activity_rows[0][1], 'the bottom footer carries the animated activity indicator')
    need(not any('▰' in line for line in turn2), 'the footer animation disappears when idle')
    need(any('✓ write the boundary test' in l for l in turn2) and any('● run the suite' in l for l in turn2) and any('○ update the docs' in l for l in turn2), 'the todo list is a checklist above the prompt')
    need(not any('todo 1/3' in l for l in turn2), 'the one-line todo status gives way to the checklist')
    need(any(l.startswith(' ~/project') and '±2' in l for l in turn2), 'the footer counts changed paths beside the branch')
    need(any(l.strip() == '↳ echo rewritten-me' for l in turn2 + rows('06a-running')) or '↳ echo rewritten-me' in text('06-turn2'), 'a command a hook rewrote shows what ran under the one the model asked for')
    heredoc = next((l for l in (out / '06-turn2.ansi').read_text().split('\n') if 'func' in l and 'Add' in l and 'return' in l), '')
    segments = re.findall(r'\x1b\[38;2;(\d+;\d+;\d+)m\x1b\[48;2;[\d;]+m([^\x1b]*)', heredoc)
    need(len({color for color, piece in segments if piece.strip()}) >= 3, f'a file written through a heredoc is coloured as its language, saw {len({color for color, piece in segments if piece.strip()})} colours in the body line')
    ansi = (out / '02-turn.ansi').read_text().split('\n')
    row = next((l for l in ansi if 'return' in l and '<=' in l), '')
    segments = re.findall(r'\x1b\[38;2;(\d+;\d+;\d+)m\x1b\[48;2;[\d;]+m([^\x1b]*)', row)
    first = next((n for n, (_, text) in enumerate(segments) if 'return' in text), len(segments))
    colors = {color for color, text in segments[first:] if text.strip()}
    need(len(colors) >= 2, f'diff rows carry syntax colours: the keyword and the rest of the line differ, saw {len(colors)} colour(s)')
    need(any(l.startswith('   - ') or '  -  ' in l or l.strip().startswith('2 -') for l in full.split('\n')) and any(l.strip().startswith('2 +') for l in full.split('\n')), 'edit shows a diff with both signs')
    need(any(l.startswith('┃  Yes, add the boundary test') for l in typing), 'typed text lines up with the transcript column')
    need(any('settings' in l for l in slash) and any('model' in l for l in slash), 'slash menu opens below the panel')
    need(any(l.startswith('┃  abcXdef') for l in rows('11-click')), 'a mouse click lands the cursor at the clicked column, past the bar and padding')
    for name in ('00-startup', '02-turn', '03-composing', '05-slash', '06-turn2'):
        need(not LEAKS[name], f'{name}: no text in the terminal default foreground, first {LEAKS[name][:3]}')
    if fails:
        print('FAIL'); [print(' -', f) for f in fails]; sys.exit(1)
    print('PASS: opencode-style contract')
try:
    if args.check: check()
finally:
    os.kill(pid, signal.SIGTERM); (out / 'raw.bin').write_bytes(bytes(raw)); print('captures in', out)
