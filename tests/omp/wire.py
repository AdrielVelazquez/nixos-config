"""Source-built OMP + real managed factory, fake direct gateway and owned proxy."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import signal
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.request import Request, urlopen

RPC = '/api/reddit.llmplatform.controlplane.project.v1alpha.ProjectService/GetOrCreateUserProject'

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args): pass
    def respond(self, value, content='application/json'):
        raw = value.encode() if isinstance(value, str) else json.dumps(value).encode()
        self.send_response(200); self.send_header('Content-Type', content)
        self.send_header('Content-Length', str(len(raw))); self.end_headers(); self.wfile.write(raw)
    def do_GET(self): self.handle_request()
    def do_POST(self): self.handle_request()
    def handle_request(self):
        raw = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        if self.server.proxy:
            if self.path == '/health': return self.respond({'status': 'ok'})
            assert self.path in ['/v1/chat/completions', '/v1/responses'], self.path
            original = '/v1/openai' + self.path.removeprefix('/v1')
            assert self.headers['x-headroom-original-path'] == original
            assert self.headers['x-headroom-base-url'] == os.environ['OMP_FIXTURE_GATEWAY']
            if b'OMP_KILL_PROXY_PROBE' in raw:
                Path(os.environ['OMP_FIXTURE_KILLED']).write_text('owned proxy reached and stopped')
                os.kill(os.getpid(), signal.SIGTERM)
                return
            request = Request(os.environ['OMP_FIXTURE_GATEWAY'] + original, data=raw,
                headers={'Content-Type': 'application/json', 'Authorization': self.headers['Authorization'], 'X-Fixture-Proxy': 'yes'})
            with urlopen(request, timeout=5) as response:
                return self.respond(response.read().decode(), response.headers['Content-Type'])
        body = json.loads(raw) if raw else None
        self.server.calls.append({'path': self.path, 'body': body, 'proxied': self.headers.get('X-Fixture-Proxy') == 'yes'})
        if self.path == RPC:
            assert not self.headers.get('X-Fixture-Proxy')
            return self.respond({'id': 'fixture-user'})
        assert self.headers['Authorization'] == 'Bearer project/fixture-user'
        if self.path == '/v1/openai/models':
            assert self.headers['X-LLM-Platform-Include-Metadata'] == 'true'
            return self.respond({'data': [{'id': name, 'x_llm_platform': {
                'capabilities': {'api': ['chat_completions'] if name.startswith('claude') else ['responses'],
                    'tools': True, 'reasoning': True, 'reasoning_efforts': ['none', 'low', 'medium', 'high', 'xhigh'], 'modalities': {'input': ['text']}},
                'limits': {'context_window_tokens': 100000, 'max_output_tokens': 1024}}}
                for name in ['claude-sonnet-5-5', 'gpt-6.1-sol', 'gpt-6-luna']]})
        assert self.headers.get('X-Fixture-Proxy') == 'yes', 'DIRECT INFERENCE BYPASS'
        assert body['model'] in ['claude-sonnet-5-5', 'gpt-6.1-sol', 'gpt-6-luna']
        if self.path.endswith('/chat/completions'):
            def chunk(delta, reason=None):
                return {'id': 'omp-chat', 'object': 'chat.completion.chunk', 'created': 1, 'model': body['model'],
                    'choices': [{'index': 0, 'delta': delta, 'finish_reason': reason}]}
            data = [chunk({'role': 'assistant', 'content': 'OMP_WIRE_OK'}), chunk({}, 'stop')]
            return self.respond(''.join('data: ' + json.dumps(x) + '\n\n' for x in data) + 'data: [DONE]\n\n', 'text/event-stream')
        assert self.path.endswith('/responses'), self.path
        transcript = json.dumps(body.get('input', []))
        tool = None
        child = body.get('reasoning', {}).get('effort') == 'low' and 'OMP_CHILD_READ' in transcript
        def completed(call_id):
            return any(x.get('type') == 'function_call_output' and x.get('call_id') == call_id for x in body.get('input', []) if isinstance(x, dict))
        if child:
            if not completed('omp-read-call'): tool = ('read', 'omp-read-call', {'path': 'canary.txt'})
            elif not completed('omp-write-call'): tool = ('write', 'omp-write-call', {'path': 'forbidden-write', 'content': 'MUST_NOT_WRITE'})
        elif 'OMP_TASK_PROBE' in transcript and not completed('omp-task-call'):
            tool = ('task', 'omp-task-call', {'context': 'Synthetic managed worker probe', 'tasks': [
                {'agent': 'scout', 'task': 'OMP_CHILD_READ', 'solutionSpace': 'Read the known canary; do not mutate anything.'}]})
        elif not child and 'OMP_NATIVE_ASYNC' in transcript:
            if not completed('omp-async-batch'):
                tool = ('task', 'omp-async-batch', {'context': 'Parallel native scouts', 'tasks': [
                    {'agent': 'scout', 'task': 'OMP_CHILD_READ', 'solutionSpace': 'Read canary ' + str(i)} for i in range(2)]})
            elif self.server.children_completed < 2:
                tool = ('wait', 'omp-wait-' + str(len(body['input'])), {})
            elif not completed('omp-async-followup'):
                tool = ('task', 'omp-async-followup', {'context': 'Sequential native scout', 'tasks': [
                    {'agent': 'scout', 'task': 'OMP_CHILD_READ', 'solutionSpace': 'Read the canary again'}]})
            elif self.server.children_completed < 3:
                tool = ('wait', 'omp-wait-' + str(len(body['input'])), {})
        if tool:
            item = {'id': 'fc-' + tool[1], 'type': 'function_call', 'call_id': tool[1], 'name': tool[0], 'arguments': json.dumps(tool[2])}
        else:
            output = 'OMP_CHILD_READ_OK' if child else 'OMP_WIRE_OK'
            if child: self.server.children_completed += 1
            if body['model'] == 'gpt-6-luna' and '<title>' in transcript:
                output = '<title>Inspect canary</title>'
            elif body['model'] == 'gpt-6-luna' and 'Compress into one routing hint' in transcript:
                output = 'Use for focused workflow tasks.'
            item = {'id': 'omp-msg', 'type': 'message', 'status': 'completed', 'role': 'assistant',
                'content': [{'type': 'output_text', 'text': output, 'annotations': []}]}
        response = {'id': 'omp-response', 'object': 'response', 'created_at': 1, 'status': 'completed',
            'model': body['model'], 'output': [item], 'usage': {'input_tokens': 10, 'output_tokens': 3, 'total_tokens': 13}}
        if tool:
            events = [{'type': 'response.created', 'response': {**response, 'status': 'in_progress', 'output': []}},
                {'type': 'response.output_item.added', 'output_index': 0, 'item': {**item, 'arguments': ''}},
                {'type': 'response.function_call_arguments.delta', 'output_index': 0, 'item_id': item['id'], 'delta': item['arguments']},
                {'type': 'response.output_item.done', 'output_index': 0, 'item': item},
                {'type': 'response.completed', 'response': response}]
        else: events = [{'type': 'response.created', 'response': {**response, 'status': 'in_progress', 'output': []}},
            {'type': 'response.output_item.added', 'output_index': 0, 'item': {**item, 'status': 'in_progress', 'content': []}},
            {'type': 'response.content_part.added', 'item_id': item['id'], 'output_index': 0, 'content_index': 0,
                'part': {'type': 'output_text', 'text': '', 'annotations': []}},
            {'type': 'response.output_text.delta', 'item_id': item['id'], 'output_index': 0, 'content_index': 0, 'delta': 'OMP_WIRE_OK'},
            {'type': 'response.output_item.done', 'output_index': 0, 'item': item},
            {'type': 'response.completed', 'response': response}]
        return self.respond(''.join('event: ' + e['type'] + '\ndata: ' + json.dumps(e) + '\n\n' for e in events), 'text/event-stream')

if sys.argv[1:2] == ['proxy']:
    server = ThreadingHTTPServer(('127.0.0.1', int(sys.argv[sys.argv.index('--port') + 1])), Handler)
    server.proxy = True; server.serve_forever()
else:
    assert os.environ.get('NIX_BUILD_TOP'), 'Native OMP execution belongs in Nix sandbox'
    spec = json.loads(Path(sys.argv[1]).read_text())
    with tempfile.TemporaryDirectory(prefix='omp-wire-', dir=os.environ['TMPDIR']) as folder:
        root = Path(folder)
        for name in ['home', 'runtime', 'project', 'tmp', 'config', 'cache', 'data', 'state']:
            (root / name).mkdir(mode=0o700)
        agent = root / 'home/.omp/agent'; agent.mkdir(parents=True)
        settings = dict(spec['settings'])
        (agent / 'models.yml').write_text(Path(spec['modelsFile']).read_text())
        (agent / 'extensions').mkdir()
        (agent / 'extensions/tuios.ts').write_text(Path(spec['tuiosFile']).read_text())
        (agent / 'mcp.json').write_text('{"mcpServers":{}}')
        (agent / 'agents').mkdir()
        for name, text in spec['agents'].items():
            # Grant an extra builtin in the fixture, simulating additive tool
            # widening: the native extension gate, not the markdown list, must deny it.
            if name == 'scout':
                text = text.replace('tools: [read, find, grep, glob, web_search]', 'tools: [read, write]\nblocking: true')
            (agent / 'agents' / (name + '.md')).write_text(text)
        (root / 'project/canary.txt').write_text('CHILD_NATIVE_READ_CANARY\n')
        gateway = ThreadingHTTPServer(('127.0.0.1', 0), Handler); gateway.proxy = False; gateway.calls = []; gateway.children_completed = 0
        thread = threading.Thread(target=gateway.serve_forever, daemon=True); thread.start()
        env = {'PATH': os.environ['PATH'], 'HOME': str(root / 'home'), 'TMPDIR': str(root / 'tmp'),
            'XDG_RUNTIME_DIR': str(root / 'runtime'), 'PI_CONFIG_DIR': '.omp', 'PI_CODING_AGENT_DIR': str(agent),
            'OMP_FIXTURE_GATEWAY': f'http://127.0.0.1:{gateway.server_port}', 'HF_HUB_OFFLINE': '1', 'TRANSFORMERS_OFFLINE': '1',
            'OMP_FIXTURE_KILLED': str(root / 'proxy-killed'),
            **{'XDG_' + name.upper() + '_HOME': str(root / name) for name in ['config', 'cache', 'data', 'state']}}
        manifest = root / 'headroom.json'
        manifest.write_text(json.dumps({'version': 1, 'client': 'omp', 'piCommand': [spec['omp']],
            'proxyCommand': [spec['python'], '-E', str(Path(__file__).resolve())], 'memory': False, 'codeGraph': False,
            'startupTimeout': 5, 'upstreamOrigins': [env['OMP_FIXTURE_GATEWAY']], 'port': 0, 'adapters': []}))
        options = {'gatewayOrigin': env['OMP_FIXTURE_GATEWAY'], 'allowTestLoopback': True,
            'python': spec['python'], 'helper': spec['helper'], 'manifest': str(manifest), 'routes': spec['routes'], 'bootstrap': 'OMP_NATIVE_BOOTSTRAP'}
        entry = root / 'work.ts'
        env['LLM_PLATFORM_PROJECT_ID'] = 'fixture-user'
        entry.write_text('import {installWork} from ' + json.dumps(spec['entrySource']) + ';\n'
            + 'import {resolveOptions} from ' + json.dumps(spec['projectOptionsSource']) + ';\n'
            + 'export default pi => installWork(pi,{...' + json.dumps(options)
            + ',projectId:resolveOptions({},process.env).projectId});\n')
        settings['extensions'] = [str(entry)]
        (agent / 'config.yml').write_text(json.dumps(settings))
        (agent / 'managed-work.json').write_text('{"version":1,"source":"Nix"}')
        try:
            for overrides, error in [({'PI_CONFIG_DIR': '.pi'}, 'inherited PI_CONFIG_DIR'),
                ({'OMP_PROFILE': 'foreign'}, 'named profiles'),
                ({'PI_CODING_AGENT_DIR': spec['piAgentDir']}, "Pi's agent directory"),
                ({'PI_CODING_AGENT_DIR': str(root / 'missing')}, 'no real-home fallback')]:
                result = subprocess.run([spec['wrapper'], '--version'], env={**env, **overrides}, text=True, capture_output=True, timeout=10)
                assert result.returncode != 0 and error in result.stderr, result.stderr
            result = subprocess.run([spec['wrapper'], '--version'], env=env, text=True, capture_output=True, timeout=15)
            assert result.returncode == 0 and '18.12.6' in result.stdout, result.stderr
            result = subprocess.run([spec['githubAuth']], env={**env, 'CODEX_GITHUB_PERSONAL_ACCESS_TOKEN': 'synthetic-token'}, text=True, capture_output=True, timeout=10)
            assert result.returncode == 0 and result.stdout == 'Bearer synthetic-token'
            for model in ['claude-sonnet-5-5', 'gpt-6.1-sol', None]:
                before = len(gateway.calls)
                command = [spec['omp'], '--print', '--no-session', '--no-tools', '--no-lsp']
                if model:
                    command += ['--model', 'llmplatform/' + model, '--thinking', 'high']
                result = subprocess.run(command + ['Reply OMP_WIRE_OK.'],
                    env=env, cwd=root / 'project', text=True, capture_output=True, timeout=70)
                if result.returncode or 'OMP_WIRE_OK' not in result.stdout:
                    print(json.dumps({'stdout': result.stdout, 'stderr': result.stderr, 'calls': gateway.calls}, indent=2), file=sys.stderr)
                assert result.returncode == 0, result.stderr
                assert 'OMP_WIRE_OK' in result.stdout, result.stdout
                assert 'Failed to load extension' not in result.stderr
                if model is None:
                    actual = next(c for c in gateway.calls[before:] if c['proxied'])
                    assert actual['body']['model'] == 'gpt-6.1-sol'
                    assert actual['body']['reasoning']['effort'] == 'high'
            inference = [c for c in gateway.calls if c['path'].endswith(('/chat/completions', '/responses'))]
            assert {c['path'] for c in inference} == {'/v1/openai/chat/completions', '/v1/openai/responses'}
            assert all(c['proxied'] for c in inference)
            main_calls = [c for c in inference if 'Reply OMP_WIRE_OK.' in json.dumps(c['body'])]
            assert len(main_calls) == 3 and all('OMP_NATIVE_BOOTSTRAP' in json.dumps(c['body']) for c in main_calls), 'main bootstrap not installed through settings'
            before = len(gateway.calls)
            result = subprocess.run([spec['omp'], '--print', '--no-session', '--no-lsp',
                '--tools', 'task,read', '--model', 'llmplatform/gpt-6.1-sol', '--thinking', 'high', 'OMP_TASK_PROBE'],
                env=env, cwd=root / 'project', text=True, capture_output=True, timeout=90)
            child_calls = [c for c in gateway.calls[before:] if c['proxied'] and c['body'].get('reasoning', {}).get('effort') == 'low']
            if result.returncode or not child_calls:
                print(json.dumps({'stdout': result.stdout, 'stderr': result.stderr, 'calls': gateway.calls[before:]}, indent=2), file=sys.stderr)
            assert result.returncode == 0, result.stderr
            assert 'OMP_WIRE_OK' in result.stdout, 'parent failed to continue after the native child: ' + result.stderr
            assert child_calls, 'native task did not use the pinned scout/low route'
            assert 'CHILD_NATIVE_READ_CANARY' in json.dumps(child_calls), 'native child did not actually read the fixture'
            assert 'scout may only use its explicit read-only operations' in json.dumps(child_calls), 'native child write was not refused by managed policy'
            assert not (root / 'project/forbidden-write').exists(), 'read-only child mutated the checkout'
            assert all('OMP_NATIVE_BOOTSTRAP' not in json.dumps(c['body']) for c in child_calls), 'main bootstrap entered a child'
            (agent / 'agents/scout.md').write_text(spec['agents']['scout'])
            gateway.children_completed = 0
            before = len(gateway.calls)
            result = subprocess.run([spec['omp'], '--print', '--no-session', '--no-lsp', '--tools', 'task,read,wait',
                '--model', 'llmplatform/gpt-6.1-sol', '--thinking', 'high', 'OMP_NATIVE_ASYNC'],
                env=env, cwd=root / 'project', text=True, capture_output=True, timeout=90)
            if result.returncode or gateway.children_completed != 3:
                print(json.dumps({'stdout': result.stdout, 'stderr': result.stderr, 'calls': gateway.calls[before:]}, indent=2), file=sys.stderr)
            assert result.returncode == 0 and 'OMP_WIRE_OK' in result.stdout, result.stderr
            assert gateway.children_completed == 3, 'native parallel/follow-up scout registrations lost their catalog'
            assert not (root / 'project/forbidden-write').exists()
            before = len(gateway.calls)
            # Native OMP defaults to ten exponential retries (~8 minutes). This
            # witness checks routing on failure, not the duration of that UI policy.
            retry_overlay = root / 'bounded-retry.yml'
            retry_overlay.write_text(json.dumps({'retry': {'enabled': True, 'maxRetries': 1, 'baseDelayMs': 10, 'maxDelayMs': 1000}}))
            result = subprocess.run([spec['omp'], '--print', '--no-session', '--no-tools', '--no-lsp',
                '--config', str(retry_overlay), '--model', 'llmplatform/gpt-6.1-sol', '--thinking', 'high', 'OMP_KILL_PROXY_PROBE'],
                env=env, cwd=root / 'project', text=True, capture_output=True, timeout=70)
            assert (root / 'proxy-killed').exists(), 'proxy outage witness never reached the owned transport'
            assert 'OMP_WIRE_OK' not in result.stdout
            assert not any(c['path'].endswith(('/responses', '/chat/completions')) for c in gateway.calls[before:]), 'proxy failure caused direct inference fallback'
            summaries = [c for c in gateway.calls if 'Compress into one routing hint' in json.dumps(c['body'])]
            assert all(c['proxied'] and c['body']['model'] == 'gpt-6-luna' and c['body'].get('reasoning', {}).get('effort') == 'none' for c in summaries), 'native skill summaries escaped the accepted Luna/no-reasoning proxy route'
            assert not (root / 'home/.pi').exists() and not (root / 'home/.config/opencode').exists()
            print('PASS: source-built native OMP, real managed provider/default, runtime project/catalog, Chat+Responses through owned proxy, native scout/low read+write-refusal, stopped-proxy no-direct-fallback and separate native state')
        finally:
            gateway.shutdown(); gateway.server_close(); thread.join(timeout=2)
