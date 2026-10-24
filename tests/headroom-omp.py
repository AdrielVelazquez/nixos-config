#!/usr/bin/env python3
"""Owned OMP process leases, using only fake services and disposable state."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.request

REPO = Path(__file__).resolve().parents[1]
HELPER = REPO / 'packages/headroom-pi.py'

class OmpLeaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='headroom-omp-', dir=os.environ.get('TMPDIR', '/tmp/opencode'))
        self.root = Path(self.temp.name)
        for name in ['home', 'runtime', 'project']:
            (self.root / name).mkdir(mode=0o700)
        self.env = {'PATH': os.environ['PATH'], 'HOME': str(self.root / 'home'), 'XDG_RUNTIME_DIR': str(self.root / 'runtime')}
        self.leases = []
        self.states = []

    def acquire(self, client='omp', pid=None):
        config = self.root / f'{client}.json'
        config.write_text(json.dumps({'version': 1, 'client': client, 'piCommand': [sys.executable, '-c', 'pass'],
            'proxyCommand': [sys.executable, '-E', str(REPO / 'tests/pi/fake-headroom.py')],
            'upstreamOrigins': ['https://fixture.invalid'], 'port': 0, 'startupTimeout': 5,
            'memory': False, 'codeGraph': False, 'adapters': []}))
        result = subprocess.run([sys.executable, '-E', str(HELPER), '--config', str(config), '--acquire', str(pid or os.getpid())],
            env=self.env, cwd=self.root / 'project', text=True, capture_output=True, timeout=12)
        self.assertEqual(result.returncode, 0, result.stderr)
        state = json.loads(result.stdout)
        self.leases.append(Path(state['leasePath']))
        self.states.append(state)
        return state

    def healthy(self, url):
        try:
            with urllib.request.urlopen(url + '/health', timeout=.2) as response:
                return response.status == 200
        except Exception:
            return False

    def wait_stopped(self, url):
        end = time.monotonic() + 8
        while self.healthy(url) and time.monotonic() < end:
            time.sleep(.05)
        self.assertFalse(self.healthy(url), 'proxy outlived its final owning process')

    def tearDown(self):
        for path in self.leases:
            path.unlink(missing_ok=True)
        for state in self.states:
            self.wait_stopped(state['proxyURL'])
        self.temp.cleanup()

    def test_namespace_and_idempotent_pid_acquisition(self):
        first, second = self.acquire(), self.acquire()
        self.assertEqual(first['proxyURL'], second['proxyURL'])
        self.assertEqual(first['instance'], second['instance'])
        self.assertEqual(first['leasePath'], second['leasePath'])
        self.assertIn(f'headroom-omp-{os.getuid()}', first['stateDir'])
        self.assertEqual(len(list((Path(first['stateDir']) / 'leases').glob('*.json'))), 1)
        lease = json.loads(Path(first['leasePath']).read_text())
        self.assertEqual(lease['pid'], os.getpid())
        self.assertTrue(self.healthy(first['proxyURL']))

    def test_pi_and_omp_do_not_share_registries(self):
        pi, omp = self.acquire('pi'), self.acquire('omp')
        self.assertNotEqual(pi['stateDir'], omp['stateDir'])
        self.assertNotEqual(pi['proxyURL'], omp['proxyURL'])

    def test_owner_process_exit_releases_proxy_without_session_hooks(self):
        child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'], env=self.env)
        try:
            state = self.acquire(pid=child.pid)
            self.assertTrue(self.healthy(state['proxyURL']))
        finally:
            child.terminate(); child.wait(timeout=3)
        self.wait_stopped(state['proxyURL'])

    def test_invalid_pid_does_not_acquire(self):
        config = self.root / 'invalid.json'
        config.write_text(json.dumps({'version': 1, 'client': 'omp'}))
        result = subprocess.run([sys.executable, '-E', str(HELPER), '--config', str(config), '--acquire', '-1'],
            env=self.env, cwd=self.root / 'project', text=True, capture_output=True, timeout=3)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')
        self.assertFalse((self.root / 'runtime' / f'headroom-omp-{os.getuid()}').exists())

    def test_native_service_exec_keeps_its_own_pid_lease_and_owned_environment(self):
        parent = self.acquire()
        probe = self.root / 'service.json'
        code = 'import json,os,pathlib,time; pathlib.Path(' + repr(str(probe)) + ').write_text(json.dumps({"pid":os.getpid(),"proxy":os.environ["HEADROOM_PROXY_URL"],"db":os.environ["HEADROOM_OMP_MEMORY_DB"]})); time.sleep(30)'
        child = subprocess.Popen([sys.executable, '-E', str(REPO / 'packages/headroom-service.py'),
            '--core', str(HELPER), '--config', str(self.root / 'omp.json'), '--', sys.executable, '-c', code],
            env=self.env, cwd=self.root / 'project')
        try:
            deadline = time.monotonic() + 8
            while not probe.exists() and child.poll() is None and time.monotonic() < deadline: time.sleep(.02)
            data = json.loads(probe.read_text())
            self.assertEqual(data['pid'], child.pid)
            self.assertEqual(data['proxy'], parent['proxyURL'])
            self.assertEqual(data['db'], parent['memoryDB'])
            leases = [json.loads(path.read_text()) for path in (Path(parent['stateDir']) / 'leases').glob('*.json')]
            self.assertIn(child.pid, [lease['pid'] for lease in leases])
        finally:
            child.terminate(); child.wait(timeout=3)
        self.assertTrue(self.healthy(parent['proxyURL']), 'service exit must not release parent ownership')

if __name__ == '__main__':
    unittest.main()
