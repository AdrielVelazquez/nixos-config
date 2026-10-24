"""Real Pi with rtk's own extension: bash commands are rewritten through `rtk rewrite`, and nothing breaks without rtk.

  rtk-session.py PI EXTENSION RTK OUTPUT

The provider is scripted on loopback; the extension is the file rtk's installer generated, and rtk is the real binary.
`ls -la` is the probe because rtk prints it compactly (`755 sub/`, `644 a.txt 3B`) where the shell prints permissions.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from scripted_pi import call, run  # noqa: E402

pi, extension, rtk, output = sys.argv[1:]
FILES = {"a.txt": "hi\n", "sub/b.txt": "yo\n"}
BASE_PATH = [d for d in os.environ["PATH"].split(os.pathsep) if d]


def rewritten(text):
    return "a.txt" in text and "drwx" not in text and "rw-r--r--" not in text


def plain(text):
    return "a.txt" in text and ("drwx" in text or "rw-r--r--" in text)


def with_rtk():
    steps = [
        lambda r, p: call("bash", command="ls -la"),
        lambda r, p: call("bash", command="rtk proxy ls -la"),
        lambda r, p: call("bash", command="echo no rewrite exists for this"),
    ]
    session = run(pi, "with-rtk", [extension], FILES, steps, path=[os.path.dirname(rtk), *BASE_PATH], out=output)
    assert rewritten(session.results[0]), session.results[0]
    assert plain(session.results[1]), "a command that already starts with rtk is left alone: " + session.results[1]
    assert "no rewrite exists for this" in session.results[2], session.results[2]
    print("PASS rewrite: `ls -la` runs as `rtk ls -la`, an rtk command and an unknown command run as written", flush=True)


def without_rtk():
    # Nothing on PATH named rtk: the extension reports it and every command runs as the model wrote it.
    session = run(pi, "without-rtk", [extension], FILES, [lambda r, p: call("bash", command="ls -la")], path=BASE_PATH, allow_stderr=True, out=output)
    assert plain(session.results[0]), session.results[0]
    print("PASS fail-open: without rtk on PATH the extension stands aside and the command runs unchanged", flush=True)


def disabled():
    session = run(pi, "disabled", [extension], FILES, [lambda r, p: call("bash", command="ls -la")], path=[os.path.dirname(rtk), *BASE_PATH],
                  env={"RTK_DISABLED": "1"}, out=output)
    assert plain(session.results[0]), session.results[0]
    print("PASS opt-out: RTK_DISABLED=1 runs the command as written", flush=True)


with_rtk()
without_rtk()
disabled()
print("PASS: real Pi with rtk's extension", flush=True)
