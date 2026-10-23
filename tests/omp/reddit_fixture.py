"""Synthetic gateway/control plane shared by configured Reddit CLI/TUI witnesses."""
from datetime import datetime, timezone
import base64
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
import re
from pathlib import Path
import threading
from urllib.parse import parse_qs, urlencode, urlsplit


class RedditGateway(BaseHTTPRequestHandler):
    def log_message(self, *_args): pass
    def respond(self, data, content='application/json', status=200):
        raw = data.encode() if isinstance(data, str) else json.dumps(data).encode()
        self.send_response(status)
        self.send_header('Content-Type', content)
        self.send_header('Content-Length', str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)
    def do_GET(self):
        parsed = urlsplit(self.path)
        if self.path == '/v1/openai/models':
            assert self.headers.get('Authorization', '').startswith('Bearer project/'), 'registry credential reached model discovery'
            self.server.catalog.append(self.headers.get('Authorization'))
            project = self.headers.get('Authorization')[len('Bearer project/'):]
            if project in self.server.denied_projects: return self.respond({'error': 'project execution permission denied'}, status=403)
            return self.respond({'data': [{'id': model, 'x_llm_platform': {'capabilities': {
                'api': ['chat_completions'] if model.startswith('claude') or (project == 'beta-project' and model == 'gpt-6.1-sol') else ['responses'], 'tools': True,
                'reasoning': True, 'reasoning_efforts': ['none', 'low', 'medium', 'high', 'xhigh'], 'modalities': {'input': ['text']}},
                'limits': {'context_window_tokens': 100000, 'max_output_tokens': 1024}}}
                for model in ['gpt-6.1-sol', 'gpt-6-luna', 'claude-sonnet-5-5']]})
        if self.path == '/.well-known/oauth-protected-resource/api/mcp':
            self.server.metadata += 1
            return self.respond({'resource': self.server.origin + '/api/mcp',
                'authorization_servers': [self.server.origin + '/api/oauth'],
                'scopes_supported': ['openid', 'offline_access', 'tool:slack:read', 'tool:llmp:skills:read']})
        if 'oauth-authorization-server' in parsed.path or 'openid-configuration' in parsed.path:
            return self.respond({'issuer': self.server.origin + '/api/oauth',
                'authorization_endpoint': self.server.origin + '/authorize?scope=tool:llmp:skills:read',
                'token_endpoint': self.server.origin + '/token', 'registration_endpoint': self.server.origin + '/register',
                'response_types_supported': ['code'], 'grant_types_supported': ['authorization_code', 'refresh_token'],
                'code_challenge_methods_supported': ['S256'], 'token_endpoint_auth_methods_supported': ['none']})
        if parsed.path == '/authorize':
            params = parse_qs(parsed.query)
            self.server.authorizations.append(params)
            target = params['redirect_uri'][0] + '?' + urlencode({'code': 'synthetic-code', 'state': params['state'][0]})
            self.send_response(302); self.send_header('Location', target); self.send_header('Content-Length', '0'); self.end_headers(); return
        return self.respond({}, status=404)
    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        if self.path == '/token':
            params = parse_qs(raw.decode()); self.server.tokens.append(params)
            if params.get('grant_type') == ['authorization_code']:
                challenge = base64.urlsafe_b64encode(hashlib.sha256(params['code_verifier'][0].encode()).digest()).decode().rstrip('=')
                assert challenge == self.server.authorizations[-1]['code_challenge'][0]
            return self.respond({'access_token': 'SYNTHETIC_REDDIT_ACCESS', 'refresh_token': 'SYNTHETIC_REDDIT_REFRESH',
                'token_type': 'Bearer', 'expires_in': 1 if params.get('grant_type') == ['authorization_code'] else 3600})
        body = json.loads(raw)
        if self.path == '/register':
            self.server.registrations.append(body)
            return self.respond({**body, 'client_id': 'synthetic-reddit-client', 'token_endpoint_auth_method': 'none'}, status=201)
        if self.path == '/api/mcp':
            assert not self.headers.get('Authorization', '').startswith('Bearer project/'), 'model bearer reached registry'
            if self.headers.get('Authorization') != 'Bearer SYNTHETIC_REDDIT_ACCESS':
                self.send_response(401)
                self.send_header('WWW-Authenticate', f'Bearer resource_metadata="{self.server.origin}/.well-known/oauth-protected-resource/api/mcp"')
                self.send_header('Content-Length', '0'); self.end_headers(); return
            self.server.rpc.append(body)
            if 'id' not in body: return self.respond({}, status=202)
            if body['method'] == 'initialize': value = {'protocolVersion': '2025-11-25', 'capabilities': {'tools': {}}, 'serverInfo': {'name': 'Reddit fixture', 'version': '1'}}
            elif body['method'] == 'tools/list': value = {'tools': [{'name': name, 'description': name, 'inputSchema': {
                'type': 'object', 'properties': {'query': {'type': 'string'}}, 'required': ['query']}} for name in ['slack__search', 'llmp__create_skill']]}
            elif body['method'] == 'tools/call': value = {'content': [{'type': 'text', 'text': 'REGISTRY_NATIVE_RESULT'}]}
            else: value = {}
            return self.respond({'jsonrpc': '2.0', 'id': body['id'], 'result': value})
        if self.path.endswith('QuotaService/GetQuotaStatus'):
            assert self.headers.get('Authorization') is None, 'model bearer reached quota endpoint'
            self.server.quotas.append(body)
            return self.respond({'projectId': body['projectId'], 'subject': 'QUOTA_STATUS_SUBJECT_CALLER_HUMAN_IDENTITY',
                'month': datetime.now(timezone.utc).strftime('%Y-%m'), 'usageMicrodollars': '1234567', 'hardQuotaPolicy': {
                    'enforcementMode': 'QUOTA_ENFORCEMENT_MODE_HARD_ERROR', 'identityType': 'QUOTA_IDENTITY_TYPE_HUMAN',
                    'scope': 'QUOTA_SCOPE_PROJECT', 'scopeId': body['projectId'], 'period': 'QUOTA_PERIOD_MONTHLY',
                    'amountMicrodollars': '2000000'}})
        if self.path.endswith('ProjectService/GetOrCreateUserProject'): return self.respond({'id': 'personal-project'})
        if self.path == '/v1/openai/chat/completions':
            assert self.headers.get('Authorization', '').startswith('Bearer project/'), 'registry credential reached inference'
            assert self.headers.get('X-Fixture-Proxy') == 'yes', 'managed project inference bypassed Headroom'
            self.server.inference.append(body)
            self.server.inference_projects.append(self.headers['Authorization'][len('Bearer project/'):])
            item = {'id': 'project-chat', 'object': 'chat.completion.chunk', 'created': 1, 'model': body['model'],
                'choices': [{'index': 0, 'delta': {'role': 'assistant', 'content': 'PROJECT_MODEL_OK'}, 'finish_reason': None}]}
            final = {**item, 'choices': [{'index': 0, 'delta': {}, 'finish_reason': 'stop'}]}
            return self.respond(''.join('data: ' + json.dumps(value) + '\n\n' for value in [item, final]) + 'data: [DONE]\n\n', 'text/event-stream')
        if self.path == '/v1/openai/responses':
            assert self.headers.get('Authorization', '').startswith('Bearer project/'), 'registry credential reached inference'
            assert self.headers.get('X-Fixture-Proxy') == 'yes', 'managed Reddit inference bypassed owned Headroom'
            self.server.inference.append(body)
            self.server.inference_projects.append(self.headers['Authorization'][len('Bearer project/'):])
            transcript = json.dumps(body.get('input', []))
            function = None
            probes = re.findall(r'REGISTRY_EXEC_[A-Z]+', transcript)
            probe = probes[-1] if probes else None
            call_id = 'registry-' + probe if probe else None
            if probe and body.get('tools') and body.get('model') == 'gpt-6.1-sol' and not any(item.get('type') == 'function_call_output' and item.get('call_id') == call_id for item in body.get('input', []) if isinstance(item, dict)):
                device = 'mcp__reddit_tools_llmp_create_skill' if probe.endswith('_LLMP') else 'mcp__reddit_tools_slack_search'
                function = {'id': 'fc-' + call_id, 'type': 'function_call', 'call_id': call_id, 'name': 'write',
                    'arguments': json.dumps({'path': 'xd://' + device, 'content': '{"query":"needle"}', 'i': 'Exercise authorized registry'})}
            item = {'id': 'diagnostic-msg', 'type': 'message', 'status': 'completed', 'role': 'assistant',
                'content': [{'type': 'output_text', 'text': 'REGISTRY_DONE' if 'REGISTRY_EXEC' in transcript else 'THIS_WAS_INFERENCE', 'annotations': []}]}
            if function: item = function
            response = {'id': 'diagnostic-response', 'object': 'response', 'created_at': 1, 'status': 'completed',
                'model': body['model'], 'output': [item], 'usage': {'input_tokens': 1, 'output_tokens': 1, 'total_tokens': 2}}
            events = [{'type': 'response.created', 'response': {**response, 'status': 'in_progress', 'output': []}},
                {'type': 'response.output_item.added', 'output_index': 0, 'item': {**item, 'status': 'in_progress', 'content': []}},
                {'type': 'response.content_part.added', 'item_id': item['id'], 'output_index': 0, 'content_index': 0,
                    'part': {'type': 'output_text', 'text': '', 'annotations': []}},
                {'type': 'response.output_text.delta', 'item_id': item['id'], 'output_index': 0, 'content_index': 0, 'delta': 'REGISTRY_DONE' if probe else 'THIS_WAS_INFERENCE'},
                {'type': 'response.output_item.done', 'output_index': 0, 'item': item},
                {'type': 'response.completed', 'response': response}]
            if function:
                events = [{'type': 'response.created', 'response': {**response, 'status': 'in_progress', 'output': []}},
                    {'type': 'response.output_item.added', 'output_index': 0, 'item': {**item, 'arguments': ''}},
                    {'type': 'response.function_call_arguments.delta', 'output_index': 0, 'item_id': item['id'], 'delta': item['arguments']},
                    {'type': 'response.output_item.done', 'output_index': 0, 'item': item}, {'type': 'response.completed', 'response': response}]
            return self.respond(''.join('event: ' + event['type'] + '\ndata: ' + json.dumps(event) + '\n\n' for event in events), 'text/event-stream')
        return self.respond({}, status=404)


def configured_reddit(root, spec):
    assert os.environ.get('NIX_BUILD_TOP'), 'Configured native OMP tests belong in Nix isolation'
    for name in ['home', 'runtime', 'project', 'tmp', 'cache', 'config', 'data', 'state']:
        (root / name).mkdir(mode=0o700)
    agent = root / 'home/.omp/agent'
    agent.mkdir(parents=True)
    (agent / 'mcp.json').write_text('{"mcpServers":{}}')
    server = ThreadingHTTPServer(('127.0.0.1', 0), RedditGateway)
    server.origin = f'http://127.0.0.1:{server.server_port}'
    server.catalog, server.quotas, server.inference, server.metadata = [], [], [], 0
    server.denied_projects = set()
    server.registrations, server.authorizations, server.tokens, server.rpc = [], [], [], []
    server.inference_projects = []
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    manifest = root / 'headroom.json'
    manifest.write_text(json.dumps({'version': 1, 'client': 'omp', 'piCommand': [spec['omp']],
        'proxyCommand': [spec['python'], '-E', spec['proxyScript']], 'memory': False, 'codeGraph': False,
        'startupTimeout': 5, 'upstreamOrigins': [server.origin], 'port': 0, 'adapters': []}))
    entry = root / 'work.ts'
    options = {'gatewayOrigin': server.origin, 'allowTestLoopback': True, 'python': spec['python'],
        'helper': spec['helper'], 'manifest': str(manifest), 'routes': spec['routes'], 'bootstrap': '',
        'projectId': 'opencode-dev', 'projectSelection': {'id': 'opencode-dev', 'source': 'default', 'locked': False},
        'extensionSource': str(entry), 'reddit': {'agentDir': str(agent), 'supportPath': spec['redditSupport'],
            'controlPlaneOrigin': server.origin, 'allowTestLoopback': True}}
    entry.write_text('import {installWork} from ' + json.dumps(spec['entrySource']) + ';\nexport default pi=>installWork(pi,' + json.dumps(options) + ');\n')
    settings = {**spec['settings'], 'extensions': [str(entry)], 'skills': {'enabled': False}}
    (agent / 'config.yml').write_text(json.dumps(settings))
    (agent / 'managed-work.json').write_text('{"version":1,"source":"Nix"}')
    env = {'PATH': os.environ['PATH'], 'HOME': str(root / 'home'), 'TMPDIR': str(root / 'tmp'), 'TERM': 'xterm-256color',
        'COLORTERM': 'truecolor', 'XDG_RUNTIME_DIR': str(root / 'runtime'), 'PI_CONFIG_DIR': '.omp', 'PI_CODING_AGENT_DIR': str(agent),
        'OMP_FIXTURE_GATEWAY': server.origin, 'HF_HUB_OFFLINE': '1', 'TRANSFORMERS_OFFLINE': '1',
        **{'XDG_' + name.upper() + '_HOME': str(root / name) for name in ['cache', 'config', 'data', 'state']}}
    def close(): server.shutdown(); server.server_close(); thread.join(timeout=2)
    return server, agent, env, close
