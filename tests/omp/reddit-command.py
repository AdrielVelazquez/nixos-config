import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from reddit_fixture import configured_reddit

spec = json.loads(Path(sys.argv[1]).read_text())
with tempfile.TemporaryDirectory(prefix='omp-reddit-command-', dir=os.environ['TMPDIR']) as folder:
    root = Path(folder)
    server, agent, env, close = configured_reddit(root, spec)
    try:
        for command, expected in [('/reddit status', 'Reddit LLM Platform'), ('/reddit quota', 'Used: $1.234567')]:
            before = len(server.inference)
            result = subprocess.run([spec['omp'], '--print', '--no-session', '--no-lsp', command], env=env,
                cwd=root / 'project', text=True, capture_output=True, timeout=70)
            assert result.returncode == 0, result.stderr
            assert expected in result.stderr, 'Native Reddit command was not handled: ' + result.stderr + result.stdout
            assert len(server.inference) == before, 'a Reddit control command became a model prompt'
        assert server.catalog and len(server.quotas) == 1
        assert server.metadata == 0, 'opening diagnostics contacted an opted-out registry'
        assert not (agent / 'reddit/preferences.json').exists()
        assert (agent / 'mcp.json').read_text() == '{"mcpServers":{}}'
        assert not (root / 'home/.pi').exists() and not (root / 'home/.config/opencode').exists()
        print('PASS: configured compiled OMP /reddit status and exact shared quota without inference/registry opt-in or foreign state')
    finally: close()
