import errno
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import sys
import tempfile
import time
import unittest


yazi = sys.argv.pop(1)
configs = [Path(path) for path in sys.argv[1:]]
del sys.argv[1:]


class YaziConfigTests(unittest.TestCase):
    def test_generated_configs_are_accepted_by_yazi(self):
        for config in configs:
            with self.subTest(config=str(config)), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                shutil.copyfile(config, root / "yazi.toml")
                env = {
                    **os.environ,
                    "HOME": tmp,
                    "XDG_CONFIG_HOME": tmp,
                    "XDG_CACHE_HOME": tmp,
                    "XDG_STATE_HOME": tmp,
                    "YAZI_CONFIG_HOME": tmp,
                    "TERM": "xterm-256color",
                }
                # Yazi initializes its config before handling --help, and needs
                # a controlling terminal even when no interactive UI is opened.
                pid, master = pty.fork()
                if pid == 0:
                    os.chdir(tmp)
                    os.execve(yazi, [yazi, "--help"], env)

                output = bytearray()
                status = None
                try:
                    deadline = time.monotonic() + 10
                    while time.monotonic() < deadline:
                        if select.select([master], [], [], 0.1)[0]:
                            try:
                                output.extend(os.read(master, 65536))
                            except OSError as error:
                                if error.errno != errno.EIO:
                                    raise
                        self.assertNotIn(b"Failed to parse config", output, output.decode(errors="replace"))
                        done, code = os.waitpid(pid, os.WNOHANG)
                        if done:
                            status = os.waitstatus_to_exitcode(code)
                            break
                    self.assertIsNotNone(status, "Yazi did not finish parsing the config")
                    self.assertEqual(status, 0, output.decode(errors="replace"))
                    self.assertIn(b"Usage:", output, output.decode(errors="replace"))
                finally:
                    if status is None:
                        # Parse-error prompts can ignore graceful termination.
                        os.kill(pid, signal.SIGKILL)
                        os.waitpid(pid, 0)
                    os.close(master)


unittest.main()
