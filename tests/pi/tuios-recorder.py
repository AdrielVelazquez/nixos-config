"""Replace only daemon delivery: use the real Tuios parser without contacting it."""
import json
import os
import subprocess
import sys

payload = sys.stdin.read()
result = subprocess.run([os.environ['PI_TUIOS_BINARY'], 'agent-hook', 'pi', '--explain'],
                        input=payload, text=True, capture_output=True, check=True)
entry = {'payload': json.loads(payload), 'explanation': json.loads(result.stderr.strip())}
with open(os.environ['PI_TUIOS_EVENTS'], 'a') as file:
    file.write(json.dumps(entry) + '\n')
