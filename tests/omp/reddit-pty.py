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
import tempfile
import termios
import time
import pyte
from reddit_fixture import configured_reddit

spec = json.loads(Path(sys.argv[1]).read_text())
destination = Path(sys.argv[2])
destination.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='omp-reddit-pty-', dir=os.environ['TMPDIR']) as folder:
    root = Path(folder)
    server, agent, env, close = configured_reddit(root, spec)
    cold = '--cold' in sys.argv
    if cold: server.denied_projects.add('opencode-dev')
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 42, 140, 0, 0))
    process = subprocess.Popen([spec['omp'], '--no-session', '--no-lsp'], stdin=slave, stdout=slave, stderr=slave,
        env=env, cwd=root / 'project', start_new_session=True)
    os.close(slave)
    output = bytearray()
    screen = pyte.Screen(140, 42)
    terminal = pyte.Stream(screen)
    def visible(): return '\n'.join(screen.display)
    def wait_for(predicate, label, timeout=30):
        deadline = time.monotonic() + timeout
        while not predicate():
            if process.poll() is not None: raise AssertionError(f'OMP exited during {label}: {process.returncode}')
            if time.monotonic() > deadline: raise AssertionError('Timed out waiting for ' + label)
            if select.select([master], [], [], .05)[0]:
                try:
                    data = os.read(master, 65536)
                    output.extend(data)
                    terminal.feed(data.decode(errors='replace'))
                except OSError: pass
    def send(value): os.write(master, value.encode() + b'\r')
    try:
        wait_for(lambda: ('no-model' in visible() and 'No model available matching enabledModels' in visible()) if cold else b'gpt-6.1-sol' in output, 'native composer')
        if cold:
            before = len(output)
            send('/reddit status')
            wait_for(lambda: b'Reddit LLM Platform' in output[before:] and b'unavailable' in output[before:], 'cold access failure diagnostics without fabricated models')
        before = len(output)
        send('/reddit')
        wait_for(lambda: b'Model status' in output[before:] and b'Reddit tools' in output[before:], 'native Reddit menu')
        (destination / 'menu.txt').write_bytes(output[before:])
        os.write(master, b'\x1b')
        wait_for(lambda: 'Model status' not in visible() and 'Reddit tools' not in visible(), 'menu dismissal')
        before = len(output)
        send('/reddit quota')
        wait_for(lambda: b'Used: $1.234567' in output[before:], 'shared quota UI')
        (destination / 'quota.txt').write_bytes(output[before:])
        os.write(master, b'\x1b')
        wait_for(lambda: 'Used: $1.234567' not in visible(), 'quota dismissal')
        before = len(output)
        send('/reddit project beta-project')
        if cold:
            wait_for(lambda: 'Choose a model for beta-project' in visible(), 'model selection without an accessible current project')
            os.write(master, b'\r')
        wait_for(lambda: b'beta-project' in output[before:] and b'Yes' in output[before:] and b'No' in output[before:], 'project confirmation')
        os.write(master, b'\x1b')
        wait_for(lambda: 'Switch Reddit project?' not in visible(), 'cancelled project dismissal')
        assert not (agent / 'reddit/projects.json').exists(), 'cancelled project choice was persisted'
        before = len(output)
        send('/reddit project beta-project')
        if cold:
            wait_for(lambda: 'Choose a model for beta-project' in visible(), 'second cold model selection')
            os.write(master, b'\r')
        wait_for(lambda: b'beta-project' in output[before:] and b'Yes' in output[before:] and b'No' in output[before:], 'second project confirmation')
        os.write(master, b'\r')
        choice = agent / 'reddit/projects.json'
        wait_for(lambda: choice.exists() and 'beta-project' in choice.read_text(), 'native project commit')
        before = len(output)
        send('/reddit status')
        wait_for(lambda: b'beta-project' in output[before:], 'active switched project status')
        (destination / 'project.txt').write_bytes(output[before:])
        assert 'Bearer project/beta-project' in server.catalog
        assert not server.inference, 'native Reddit controls unexpectedly called a model'
        before = len(output)
        send('Explicit synthetic post-project-switch model canary')
        wait_for(lambda: b'PROJECT_MODEL_OK' in output[before:], 'new project model/API/auth binding through Headroom')
        # The explicit Sol turn may also trigger the already-accepted native Luna title.
        assert server.inference_projects and all(project == 'beta-project' for project in server.inference_projects), server.inference_projects
        assert sum(item['model'] == 'gpt-6.1-sol' for item in server.inference) == 1
        assert all(item['model'] in ['gpt-6.1-sol', 'gpt-6-luna'] for item in server.inference)
        assert server.metadata == 0, 'opted-out registry was contacted'
        assert not (agent / 'reddit/preferences.json').exists()
        assert (agent / 'mcp.json').read_text() == '{"mcpServers":{}}'
        print('PASS: native Reddit controls need no inference; explicit post-switch model canary uses new project/API/auth through Headroom' + ('; cold denied project diagnostics/recovery verified' if cold else ''))
    except Exception:
        (destination / 'failure.txt').write_bytes(output)
        print(output.decode(errors='replace'), file=sys.stderr)
        raise
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired: os.killpg(process.pid, signal.SIGKILL); process.wait(timeout=5)
        os.close(master)
        close()
