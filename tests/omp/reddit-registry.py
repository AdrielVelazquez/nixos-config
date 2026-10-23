"""Configured /reddit -> native OAuth -> real registry RPC and execution ceilings."""
import fcntl
import json
import os
from pathlib import Path
import pty
import pyte
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time
from urllib.request import urlopen
from reddit_fixture import configured_reddit

spec = json.loads(Path(sys.argv[1]).read_text())
with tempfile.TemporaryDirectory(prefix='omp-reddit-registry-', dir=os.environ['TMPDIR']) as folder:
    root = Path(folder)
    server, agent, env, close = configured_reddit(root, spec)
    declaration = root / 'managed-mcp.json'
    declaration.write_text('{"mcpServers":{}}'); declaration.chmod(0o444)
    (agent / 'mcp.json').unlink(); (agent / 'mcp.json').symlink_to(declaration)
    (root / 'bin').mkdir()
    browser_file = root / 'browser-url'
    browser = root / 'bin/xdg-open'
    browser.write_text('#!' + sys.executable + '\nimport os,sys,pathlib\npathlib.Path(os.environ["OMP_BROWSER_URL"]).write_text(sys.argv[-1])\n')
    browser.chmod(0o755)
    env.update({'PATH': str(root / 'bin') + ':' + env['PATH'], 'OMP_BROWSER_URL': str(browser_file)})
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 45, 150, 0, 0))
    process = subprocess.Popen([spec['omp'], '--no-session', '--no-lsp'], stdin=slave, stdout=slave, stderr=slave,
        env=env, cwd=root / 'project', start_new_session=True)
    os.close(slave)
    output = bytearray(); screen = pyte.Screen(150, 45); terminal = pyte.Stream(screen)
    def visible(): return '\n'.join(screen.display)
    def wait_for(predicate, label, timeout=40):
        deadline = time.monotonic() + timeout
        while not predicate():
            if process.poll() is not None: raise AssertionError(f'OMP exited during {label}: {process.returncode}')
            if time.monotonic() > deadline: raise AssertionError('Timed out waiting for ' + label)
            if select.select([master], [], [], .05)[0]:
                try:
                    data = os.read(master, 65536); output.extend(data); terminal.feed(data.decode(errors='replace'))
                except OSError: pass
    def send(value): os.write(master, value.encode() + b'\r')
    def rpc_calls(): return [item for item in server.rpc if item['method'] == 'tools/call']
    def preferences(): return json.loads((agent / 'reddit/preferences.json').read_text())
    def probe(marker):
        before = len(server.inference)
        send(marker)
        call_id = 'registry-' + marker
        wait_for(lambda: any(request['model'] == 'gpt-6.1-sol' and any(
            item.get('type') == 'function_call_output' and item.get('call_id') == call_id
            for item in request.get('input', []) if isinstance(item, dict)) for request in server.inference[before:]), marker + ' native tool result')
    try:
        wait_for(lambda: 'gpt-6.1-sol' in visible(), 'configured native composer')
        assert server.metadata == 0 and not browser_file.exists()
        send('/reddit tools setup')
        wait_for(lambda: 'Connect Reddit tools?' in visible() and 'Yes' in visible(), 'explicit registry consent')
        os.write(master, b'\r')
        wait_for(lambda: '/mcp reauth reddit-tools' in visible(), 'native login handoff')
        assert preferences()['toolsOptIn'] is True
        assert not browser_file.exists(), 'setup submitted native browser login without explicit Enter'
        os.write(master, b'\r')
        wait_for(lambda: browser_file.exists(), 'native browser stub')
        with urlopen(browser_file.read_text(), timeout=10) as response: assert response.status == 200
        wait_for(lambda: b'Reauthorized' in output, 'native OAuth completion')
        scopes = {'openid', 'offline_access', 'tool:slack:read'}
        assert set(server.authorizations[-1]['scope'][0].split()) == scopes
        assert set(server.registrations[-1]['scope'].split()) == scopes
        assert any(item.get('grant_type') == ['refresh_token'] for item in server.tokens)
        probe('REGISTRY_EXEC_FIRST')
        assert len(rpc_calls()) == 1 and rpc_calls()[0]['params']['name'] == 'slack__search', server.rpc
        assert 'REGISTRY_NATIVE_RESULT' in json.dumps(server.inference), 'real registry result never reached inference'
        send('/reddit tools provider slack off')
        wait_for(lambda: 'slack' in preferences()['directories'].get(str(root / 'project'), {}).get('disabledProviders', []), 'directory provider opt-out')
        probe('REGISTRY_EXEC_BLOCKED')
        assert len(rpc_calls()) == 1, 'disabled provider was called through native xdev'
        probe('REGISTRY_EXEC_LLMP')
        assert len(rpc_calls()) == 1, 'first-party LLMP tool was callable by guessed name'
        send('/reddit tools provider slack on')
        wait_for(lambda: 'slack' not in preferences()['directories'].get(str(root / 'project'), {}).get('disabledProviders', []), 'directory provider opt-in')
        probe('REGISTRY_EXEC_AGAIN')
        assert len(rpc_calls()) == 2
        before = len(output)
        send('/reddit tools logout')
        wait_for(lambda: '/mcp unauth reddit-tools' in visible(), 'native logout handoff')
        os.write(master, b'\r')
        wait_for(lambda: b'Cleared auth' in output[before:], 'native sign-out')
        assert len(server.authorizations) == 1, 'tool challenge unexpectedly launched another browser authorization'
        assert (agent / 'mcp.json').is_symlink() and declaration.read_text() == '{"mcpServers":{}}'
        assert (agent / 'mcp.json').read_text() == '{"mcpServers":{}}'
        assert not (root / 'home/.pi').exists() and not (root / 'home/.config/opencode').exists()
        print('PASS: configured Reddit consent, native PKCE/refresh/logout, actual registry RPC, directory/xdev opt-out, first-party denial and owned inference')
    except Exception:
        print(json.dumps({'screen': visible(), 'terminal': output.decode(errors='replace')[-18000:],
            'rpc': server.rpc, 'authorizations': server.authorizations, 'catalog': server.catalog}, indent=2), file=sys.stderr)
        raise
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired: os.killpg(process.pid, signal.SIGKILL); process.wait(timeout=5)
        os.close(master); close()
