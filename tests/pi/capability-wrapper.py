"""Exercise the actual generated Pi wrapper with a harmless substituted launcher."""
import os
import subprocess
import sys

wrapper, default_dir = sys.argv[1:]
env = {'PATH': os.environ['PATH'], 'HOME': os.environ['TMPDIR'], 'CODEX_GITHUB_PERSONAL_ACCESS_TOKEN': 'synthetic-only'}
def run(extra):
    return subprocess.run([wrapper], env=env | extra, text=True, capture_output=True, check=True).stdout.strip()
assert run({}) == default_dir
assert run({'PI_CODING_AGENT_DIR': ''}) == default_dir
explicit = os.environ['TMPDIR'] + '/explicit-test-agent'
assert run({'PI_CODING_AGENT_DIR': explicit}) == explicit, 'explicit test directory silently replaced by real managed directory'
print('PASS: generated wrapper defaults safely and preserves an explicit isolated agent directory')
