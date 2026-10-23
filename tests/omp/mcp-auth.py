"""Native TUI OAuth against a fake registry, fake browser and disposable vault."""
import base64
import fcntl
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
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
from urllib.parse import parse_qs, urlencode, urlsplit
from urllib.request import urlopen


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args): pass
    def reply(self, data, status=200, headers=None):
        raw = json.dumps(data).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(raw)))
        for key, value in (headers or {}).items(): self.send_header(key, value)
        self.end_headers()
        self.wfile.write(raw)
    def do_GET(self):
        parsed = urlsplit(self.path)
        root = self.server.origin
        issuer = root + ('/untrusted-issuer' if self.server.bad_issuer else '/oauth')
        if 'oauth-protected-resource' in parsed.path:
            return self.reply({'resource': root + ('/untrusted-resource' if self.server.bad_resource else '/mcp'), 'authorization_servers': [issuer],
                'scopes_supported': ['openid', 'offline_access', 'tool:search:read', 'tool:llmp:skills:read']})
        if 'oauth-authorization-server' in parsed.path or 'openid-configuration' in parsed.path:
            return self.reply({'issuer': issuer, 'authorization_endpoint': root + '/authorize?scope=tool:llmp:skills:read',
                'token_endpoint': root + '/token', 'registration_endpoint': root + '/register',
                'response_types_supported': ['code'], 'grant_types_supported': ['authorization_code', 'refresh_token'],
                'code_challenge_methods_supported': ['S256'], 'token_endpoint_auth_methods_supported': ['none'],
                'scopes_supported': ['openid', 'offline_access', 'tool:search:read', 'tool:llmp:skills:read']})
        if parsed.path == '/authorize':
            params = parse_qs(parsed.query)
            self.server.authorizations.append(params)
            location = params['redirect_uri'][0] + '?' + urlencode({'code': 'synthetic-code', 'state': params['state'][0]})
            return self.reply({}, 302, {'Location': location})
        return self.reply({}, 405)
    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        if self.path == '/register':
            params = json.loads(raw)
            self.server.registrations.append(params)
            return self.reply({'client_id': 'synthetic-omp-client', 'client_id_issued_at': 0,
                'token_endpoint_auth_method': 'none', **params}, 201)
        if self.path == '/token':
            params = parse_qs(raw.decode())
            self.server.tokens.append(params)
            if params.get('grant_type') == ['authorization_code']:
                verifier = params['code_verifier'][0]
                challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip('=')
                assert challenge == self.server.authorizations[-1]['code_challenge'][0]
                assert self.server.authorizations[-1]['code_challenge_method'] == ['S256']
            return self.reply({'access_token': 'SYNTHETIC_OMP_ACCESS', 'refresh_token': 'SYNTHETIC_OMP_REFRESH',
                'token_type': 'Bearer', 'expires_in': 1 if params.get('grant_type') == ['authorization_code'] else 3600})
        if self.path == '/mcp':
            if self.headers.get('Authorization') != 'Bearer SYNTHETIC_OMP_ACCESS':
                return self.reply({'error': 'sign-in required'}, 401, {
                    'WWW-Authenticate': f'Bearer resource_metadata="{self.server.origin}/.well-known/oauth-protected-resource/mcp"'})
            request = json.loads(raw)
            self.server.rpc.append(request)
            if 'id' not in request: return self.reply({}, 202)
            value = {'protocolVersion': '2025-11-25', 'capabilities': {'tools': {}},
                'serverInfo': {'name': 'synthetic-registry', 'version': '1'}} if request['method'] == 'initialize' else {
                    'tools': [{'name': 'foreign__lookup', 'description': 'Explicit project tool', 'inputSchema': {'type': 'object', 'properties': {}}}] if self.server.foreign else []}
            return self.reply({'jsonrpc': '2.0', 'id': request['id'], 'result': value})
        self.server.unexpected.append(self.path)
        return self.reply({}, 500)


assert os.environ.get('NIX_BUILD_TOP'), 'Native auth execution requires Nix isolation'
spec = json.loads(Path(sys.argv[1]).read_text())
with tempfile.TemporaryDirectory(prefix='omp-owned-auth-', dir=os.environ['TMPDIR']) as folder:
    root = Path(folder)
    for name in ['home', 'runtime', 'project', 'tmp', 'cache', 'config', 'data', 'state', 'bin']:
        (root / name).mkdir(mode=0o700)
    agent = root / 'home/.omp/agent'
    agent.mkdir(parents=True)
    settings = {**spec['settings'], 'extensions': [spec['mcpFixture']], 'enabledModels': ['fixture/*'],
        'modelRoles': {'default': 'fixture/unit:off', 'tiny': 'fixture/unit:off'}, 'defaultThinkingLevel': 'off',
        'skills': {'enabled': False}, 'retry': {'enabled': False}}
    (agent / 'config.yml').write_text(json.dumps(settings))
    declaration = root / 'managed-mcp.json'
    declaration.write_text('{"mcpServers":{}}')
    declaration.chmod(0o444)
    (agent / 'mcp.json').symlink_to(declaration)
    url_file = root / 'browser-url'
    browser = root / 'bin/xdg-open'
    browser.write_text('#!' + sys.executable + '\nimport os,sys,pathlib\npathlib.Path(os.environ["OMP_BROWSER_URL"]).write_text(sys.argv[-1])\n')
    browser.chmod(0o755)
    for name in ['open', 'sensible-browser', 'gio']: (root / 'bin' / name).symlink_to(browser)
    state_file = root / 'state.json'
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    server.origin = f'http://127.0.0.1:{server.server_port}'
    server.bad_issuer = '--bad-issuer' in sys.argv
    server.bad_resource = '--bad-resource' in sys.argv
    server.foreign = False
    server.registrations, server.authorizations, server.tokens, server.rpc, server.unexpected = [], [], [], [], []
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    env = {'PATH': str(root / 'bin') + ':' + os.environ['PATH'], 'HOME': str(root / 'home'), 'TMPDIR': str(root / 'tmp'),
        'TERM': 'xterm-256color', 'COLORTERM': 'truecolor', 'XDG_RUNTIME_DIR': str(root / 'runtime'),
        'PI_CONFIG_DIR': '.omp', 'PI_CODING_AGENT_DIR': str(agent), 'OMP_MCP_AUTH_MODE': '1',
        'OMP_MCP_STATE': str(state_file), 'OMP_MCP_GATEWAY': server.origin, 'OMP_BROWSER_URL': str(url_file),
        'BROWSER': str(browser), 'HF_HUB_OFFLINE': '1', 'TRANSFORMERS_OFFLINE': '1',
        **{'XDG_' + name.upper() + '_HOME': str(root / name) for name in ['cache', 'config', 'data', 'state']}}
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 140, 0, 0))
    process = subprocess.Popen([spec['omp'], '--no-session', '--no-lsp', '--model', 'fixture/unit', '--thinking', 'off'],
        stdin=slave, stdout=slave, stderr=slave, cwd=root / 'project', env=env, start_new_session=True)
    os.close(slave)
    output = bytearray()
    def wait_for(predicate, label, timeout=35):
        deadline = time.monotonic() + timeout
        while not predicate():
            if process.poll() is not None: raise AssertionError(f'OMP exited while waiting for {label}: {process.returncode}')
            if time.monotonic() >= deadline: raise AssertionError('Timed out waiting for ' + label)
            if select.select([master], [], [], .05)[0]:
                try: output.extend(os.read(master, 65536))
                except OSError: pass
    def send(command): os.write(master, command.encode() + b'\r')
    def state(): return json.loads(state_file.read_text()) if state_file.exists() else {}
    def unchanged():
        assert (agent / 'mcp.json').is_symlink(), 'native MCP control replaced the managed symlink'
        assert declaration.read_text() == '{"mcpServers":{}}'
        assert (agent / 'mcp.json').read_text() == '{"mcpServers":{}}'
    try:
        wait_for(lambda: state_file.exists(), 'native runtime registration')
        wait_for(lambda: b'unit' in output, 'native composer startup')
        assert not state().get('error'), state()
        assert not url_file.exists(), 'registration silently launched browser auth'
        send('/mcp reauth reddit-tools')
        wait_for(lambda: url_file.exists() or b'Failed to reauthorize server' in output, 'native OAuth browser handoff or metadata refusal')
        if server.bad_issuer or server.bad_resource:
            assert not url_file.exists(), 'native OAuth accepted metadata outside the pinned issuer/resource'
            assert not server.registrations and not server.tokens, 'untrusted issuer reached client registration/token exchange'
            unchanged()
            print('PASS: native owned OAuth refuses untrusted issuer/resource metadata before browser/client/token actions')
            raise SystemExit(0)
        auth_url = url_file.read_text()
        with urlopen(auth_url, timeout=10) as response: assert response.status == 200
        wait_for(lambda: b'Reauthorized' in output, 'native OAuth completion')
        expected = {'openid', 'offline_access', 'tool:search:read'}
        failures = []
        if set(server.authorizations[-1].get('scope', [''])[0].split()) != expected: failures.append('native authorization ignored filtered scopes')
        if set(server.registrations[-1].get('scope', '').split()) != expected: failures.append('native DCR ignored filtered scopes')
        if not (agent / 'mcp.json').is_symlink(): failures.append('native auth replaced the managed MCP symlink')
        if (agent / 'mcp.json').read_text() != '{"mcpServers":{}}': failures.append('native auth wrote an unrequested MCP declaration')
        assert not failures, failures
        assert server.tokens and not server.unexpected, server.unexpected
        assert any(item.get('grant_type') == ['refresh_token'] for item in server.tokens), 'native refresh was not exercised'
        unchanged()
        send('/native-mcp-state')
        wait_for(lambda: any(item['authState'] == 'stored' and item['extensionOwned'] for item in state().get('servers', [])), 'native OMP vault binding')
        for verb in ['disable', 'enable', 'remove']:
            before = len(output)
            send('/mcp ' + verb + ' reddit-tools')
            wait_for(lambda: b'runtime-owned' in output[before:], 'owned native ' + verb + ' refusal')
            unchanged()
        # A cancelled second sign-in must retain the already-authorized vault row.
        url_file.unlink()
        before = len(output)
        token_count = len(server.tokens)
        send('/mcp reauth reddit-tools')
        wait_for(lambda: url_file.exists(), 'second OAuth handoff')
        os.write(master, b'\x1b')
        wait_for(lambda: b'cancelled' in output[before:], 'native OAuth cancellation')
        assert len(server.tokens) == token_count, 'cancelled sign-in exchanged a token'
        unchanged()
        revision = state().get('revision', 0)
        send('/native-mcp-state')
        wait_for(lambda: state().get('revision', 0) > revision and any(item['authState'] == 'stored' for item in state().get('servers', [])), 'cancel retains prior native credentials')
        send('/mcp unauth reddit-tools')
        wait_for(lambda: b'Cleared auth' in output, 'native sign-out')
        unchanged()
        send('/native-mcp-state')
        wait_for(lambda: all(item['authState'] == 'none' for item in state().get('servers', [])), 'signed-out native vault')
        # A real project declaration can supersede the runtime layer on reload.
        # Cleanup of the old extension must never disconnect that new owner.
        project_config = root / 'project/.omp/mcp.json'
        project_config.parent.mkdir(exist_ok=True)
        foreign = json.dumps({'mcpServers': {'reddit-tools': {'type': 'http', 'url': server.origin + '/mcp',
            'headers': {'Authorization': 'Bearer SYNTHETIC_OMP_ACCESS'}}}})
        project_config.write_text(foreign)
        server.foreign = True
        before = len(output)
        rpc_count = len(server.rpc)
        send('/mcp reload')
        wait_for(lambda: b'MCP reload complete' in output[before:] and len(server.rpc) > rpc_count + 1, 'foreign project server reload')
        revision = state().get('revision', 0)
        send('/native-mcp-state')
        wait_for(lambda: state().get('revision', 0) > revision, 'foreign owner snapshot')
        assert any(item['name'] == 'reddit-tools' and not item['extensionOwned'] and item['status'] == 'connected' for item in state().get('servers', [])), state()
        foreign_tool = next(item['name'] for server_state in state()['servers'] for item in server_state['tools'] if item['originalName'] == 'foreign__lookup')
        failures = []
        if foreign_tool not in state().get('nativeTools', []): failures.append('inactive runtime layer hid the replacement project tool')
        revision = state().get('revision', 0)
        send('/native-mcp-remove')
        wait_for(lambda: state().get('revision', 0) > revision, 'stale runtime owner cleanup')
        revision = state().get('revision', 0)
        send('/native-mcp-state')
        wait_for(lambda: state().get('revision', 0) > revision, 'snapshot after stale cleanup')
        if not any(item['name'] == 'reddit-tools' and not item['extensionOwned'] and item['status'] == 'connected' for item in state().get('servers', [])): failures.append('stale extension cleanup disconnected the replacement project server')
        assert not failures, failures
        assert project_config.read_text() == foreign
        assert not (root / 'home/.pi').exists() and not (root / 'home/.config/opencode').exists()
        print('PASS: compiled OMP native OAuth/PKCE/refresh, filtered scopes, vault binding, immutable controls, cancelled reauth retains credentials and logout')
    except Exception:
        print(json.dumps({'terminal': output.decode(errors='replace'), 'state': state(), 'registrations': server.registrations,
            'authorizations': server.authorizations, 'tokenGrants': [item.get('grant_type') for item in server.tokens]}, indent=2), file=sys.stderr)
        raise
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired: os.killpg(process.pid, signal.SIGKILL); process.wait(timeout=5)
        os.close(master)
        server.shutdown(); server.server_close(); worker.join(timeout=2)
