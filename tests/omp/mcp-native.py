"""Compiled OMP runtime-MCP API witness; only disposable fake services/state."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args): pass

    def respond(self, data, content='application/json', status=200):
        raw = data.encode() if isinstance(data, str) else json.dumps(data).encode()
        self.send_response(status)
        self.send_header('Content-Type', content)
        self.send_header('Content-Length', str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self): self.respond({}, status=405)

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))))
        if self.path == '/mcp':
            self.server.rpc.append(body)
            if 'id' not in body: return self.respond('', status=204)
            method = body['method']
            if method == 'initialize':
                value = {'protocolVersion': '2025-11-25', 'capabilities': {'tools': {}},
                    'serverInfo': {'name': 'synthetic-registry', 'version': '1'}}
            elif method == 'tools/list':
                value = {'tools': [{'name': name, 'description': name, 'inputSchema': {
                    'type': 'object', 'properties': {'query': {'type': 'string'}}, 'required': ['query']}}
                    for name in ['search__lookup', 'search__denied']]}
            elif method == 'tools/call':
                value = {'content': [{'type': 'text', 'text': 'OMP_MCP_RESULT_CANARY'}]}
            else: value = {}
            return self.respond({'jsonrpc': '2.0', 'id': body['id'], 'result': value})
        assert self.path == '/v1/chat/completions', self.path
        self.server.inference.append(body)
        state = json.loads(self.server.state.read_text()) if self.server.state.exists() else {}
        transcript = json.dumps(body['messages'])
        delta = {'content': 'OMP_NATIVE_MCP_OK'}
        reason = 'stop'
        if 'ONLY_MCP_CHILD_SYSTEM' in transcript:
            delta = {'content': 'NATIVE_MCP_CHILD_OK'}
        elif 'OMP_NATIVE_MCP_LIFECYCLE' in transcript:
            def completed(call_id):
                return any(msg.get('role') == 'tool' and msg.get('tool_call_id') == call_id for msg in body['messages'])
            stage = None
            if not completed('children-batch'): stage = ('children-batch', 2)
            elif not completed('children-followup'): stage = ('children-followup', 1)
            if stage:
                call_id, count = stage
                arguments = {'context': 'Exercise inherited native MCP ownership', 'tasks': [
                    {'agent': 'native-mcp-child', 'task': 'Return the fixture result', 'solutionSpace': str(i)} for i in range(count)]}
                delta = {'tool_calls': [{'index': 0, 'id': call_id, 'type': 'function',
                    'function': {'name': 'task', 'arguments': json.dumps(arguments)}}]}
                reason = 'tool_calls'
        if ('OMP_NATIVE_MCP_PROBE' in transcript or 'OMP_NATIVE_MCP_LIFECYCLE' in transcript) and reason == 'stop' and 'ONLY_MCP_CHILD_SYSTEM' not in transcript and not state.get('error'):
            server = next((item for item in state.get('servers', []) if item['name'] == 'reddit-tools'), {})
            for original, call_id in [('search__lookup', 'lookup-call'), ('search__denied', 'denied-call')]:
                if any(msg.get('role') == 'tool' and msg.get('tool_call_id') == call_id for msg in body['messages']): continue
                name = next((tool['name'] for tool in server.get('tools', []) if tool['originalName'] == original), None)
                if name:
                    arguments = {'query': 'needle'}
                    if self.server.xdev:
                        arguments = {'path': 'xd://' + name, 'content': json.dumps(arguments), 'i': 'Exercise native MCP device'}
                        name = 'write'
                    delta = {'tool_calls': [{'index': 0, 'id': call_id, 'type': 'function',
                        'function': {'name': name, 'arguments': json.dumps(arguments)}}]}
                    reason = 'tool_calls'
                break
        chunk = {'id': 'native-mcp-chat', 'object': 'chat.completion.chunk', 'created': 1,
            'model': 'unit', 'choices': [{'index': 0, 'delta': {'role': 'assistant', **delta}, 'finish_reason': None}]}
        finish = {**chunk, 'choices': [{'index': 0, 'delta': {}, 'finish_reason': reason}]}
        return self.respond(''.join('data: ' + json.dumps(item) + '\n\n' for item in [chunk, finish])
            + 'data: [DONE]\n\n', 'text/event-stream')


assert os.environ.get('NIX_BUILD_TOP'), 'Execute the compiled MCP witness only in Nix isolation'
spec = json.loads(Path(sys.argv[1]).read_text())
with tempfile.TemporaryDirectory(prefix='omp-native-mcp-', dir=os.environ['TMPDIR']) as directory:
    root = Path(directory)
    for name in ['home', 'runtime', 'project', 'tmp', 'cache', 'config', 'data', 'state']:
        (root / name).mkdir(mode=0o700)
    agent = root / 'home/.omp/agent'
    agent.mkdir(parents=True)
    settings = {**spec['settings'], 'extensions': [spec['mcpFixture']], 'enabledModels': ['fixture/*'],
        'modelRoles': {'default': 'fixture/unit:off', 'tiny': 'fixture/unit:off'}, 'defaultThinkingLevel': 'off',
        'skills': {'enabled': False}, 'tools': {'xdev': '--xdev' in sys.argv}, 'retry': {'enabled': False}}
    if '--lifecycle' in sys.argv:
        settings['task'] = {**settings['task'], 'agentModelOverrides': {'native-mcp-child': 'fixture/unit:off'}}
        (agent / 'agents').mkdir()
        (agent / 'agents/native-mcp-child.md').write_text('---\nname: native-mcp-child\ndescription: Native ownership fixture\nmodel: fixture/unit:off\nblocking: true\ntools: [read]\nprewalk: false\nadvisor: false\n---\nONLY_MCP_CHILD_SYSTEM\n')
    (agent / 'config.yml').write_text(json.dumps(settings))
    (agent / 'mcp.json').write_text('{"mcpServers":{}}')
    foreign = root / 'foreign.ts'
    foreign.write_text('import {readFileSync,writeFileSync} from "node:fs";\nexport default pi => pi.on("session_start",async(_event,ctx)=>{if(ctx.agent.kind!=="main")return;'
        'let state=JSON.parse(readFileSync(process.env.OMP_MCP_STATE,"utf8"));'
        'try{await pi.registerMcpServer("reddit-tools",{type:"http",url:process.env.OMP_MCP_GATEWAY+"/mcp"});state.collisionRefused=false;}'
        'catch(e){state.collisionRefused=/owned|collision|already/i.test(e.message);}'
        'writeFileSync(process.env.OMP_MCP_STATE,JSON.stringify(state));});\n')
    settings['extensions'].append(str(foreign))
    (agent / 'config.yml').write_text(json.dumps(settings))
    state_path = root / 'results.json'
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    server.state = state_path
    server.xdev = '--xdev' in sys.argv
    server.rpc, server.inference = [], []
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    env = {'PATH': os.environ['PATH'], 'HOME': str(root / 'home'), 'TMPDIR': str(root / 'tmp'),
        'XDG_RUNTIME_DIR': str(root / 'runtime'), 'PI_CONFIG_DIR': '.omp', 'PI_CODING_AGENT_DIR': str(agent),
        'OMP_MCP_STATE': str(state_path), 'OMP_MCP_GATEWAY': f'http://127.0.0.1:{server.server_port}',
        'HF_HUB_OFFLINE': '1', 'TRANSFORMERS_OFFLINE': '1',
        **{'XDG_' + name.upper() + '_HOME': str(root / name) for name in ['cache', 'config', 'data', 'state']}}
    try:
        result = subprocess.run([spec['omp'], '--print', '--no-session', '--no-lsp', '--model', 'fixture/unit',
            '--thinking', 'off', 'OMP_NATIVE_MCP_LIFECYCLE' if '--lifecycle' in sys.argv else 'OMP_NATIVE_MCP_PROBE'], cwd=root / 'project', env=env,
            text=True, capture_output=True, timeout=75)
        state = json.loads(state_path.read_text()) if state_path.exists() else {}
        assert result.returncode == 0, result.stderr
        assert not state.get('error'), 'Native MCP registration unavailable: ' + str(state.get('error'))
        assert state.get('collisionRefused'), 'another extension stole the runtime server'
        assert any(request['method'] == 'tools/list' for request in server.rpc)
        calls = [request['params']['name'] for request in server.rpc if request['method'] == 'tools/call']
        assert calls == ['search__lookup'], calls
        assert 'OMP_MCP_RESULT_CANARY' in json.dumps(server.inference), 'no real native tool result reached the model'
        assert 'OMP_NATIVE_POLICY_DENIED' in json.dumps(server.inference), 'denied native call did not reach its execution guard'
        assert state.get('policyCwd') == str(root / 'project'), state
        if '--lifecycle' in sys.argv:
            assert state.get('childMutationRefusals', 0) >= 3 and not state.get('childMutationAccepted'), state
        removed = subprocess.run([spec['omp'], '--print', '--no-session', '--no-lsp', '--model', 'fixture/unit',
            '--thinking', 'off', '/native-mcp-remove'], cwd=root / 'project', env=env,
            text=True, capture_output=True, timeout=40)
        state = json.loads(state_path.read_text())
        assert removed.returncode == 0, removed.stderr
        assert state.get('removed'), state
        assert 'OMP_NATIVE_MCP_OK' in result.stdout, result.stdout
        assert (agent / 'mcp.json').read_text() == '{"mcpServers":{}}'
        assert not (root / 'home/.pi').exists() and not (root / 'home/.config/opencode').exists()
        print('PASS: compiled OMP owned runtime MCP registration, real tool call, deny guard, owner collision, removal and config preservation')
    except Exception:
        print(json.dumps({'stdout': result.stdout, 'stderr': result.stderr, 'state': state, 'rpc': server.rpc,
            'inference': server.inference}, indent=2), file=sys.stderr)
        raise
    finally:
        server.shutdown()
        server.server_close()
        worker.join(timeout=2)
