"""Real managed Pi skin with localized, bounded, collapsible todo widgets."""

import codecs
import fcntl
import json
import os
import pty
import select
import signal
import struct
import sys
import termios
import time
from pathlib import Path

import pyte

sys.dont_write_bytecode = True
from scripted_pi import Scripted, call, launch, prepare

pi, fixture_file, output = sys.argv[1:]
fixture = json.loads(Path(fixture_file).read_text())
out = Path(output)
out.mkdir(parents=True, exist_ok=True)
runroot, home, agent, project = prepare(
    "todo-ui",
    [*fixture["uiEntries"], fixture["todoUiEntry"]],
    {},
    {"theme": "dark"},
    None,
)
events = runroot / "settled.jsonl"
probe = runroot / "observe.ts"
probe.write_text("""import {appendFileSync} from 'node:fs';
export default pi => pi.on('agent_settled', () => appendFileSync(process.env.TODO_UI_EVENTS, 'settled\\n'));""")
scripted = Scripted([], "todo-ui", project)
args, env = launch(
    pi,
    runroot,
    home,
    agent,
    scripted,
    None,
    None,
    {"TERM": "xterm-256color", "COLORTERM": "truecolor", "TODO_UI_EVENTS": str(events)},
    ["--tui-mode", "fullscreen", "-e", str(probe)],
)
pid, master = pty.fork()
if pid == 0:
    os.chdir(project)
    os.execve(pi, args, env)
screen = pyte.Screen(100, 40)
stream = pyte.Stream(screen)
decoder = codecs.getincrementaldecoder("utf-8")("replace")
raw = bytearray()


def resize(cols, rows):
    fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    screen.resize(rows, cols)
    os.kill(pid, signal.SIGWINCH)


def pump(seconds=0.2):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if select.select([master], [], [], 0.05)[0]:
            try:
                data = os.read(master, 65536)
            except OSError:
                return
            raw.extend(data)
            stream.feed(decoder.decode(data))


def prompt(text, *calls):
    previous = len(events.read_text().splitlines()) if events.exists() else 0
    scripted.steps = [lambda results, project, value=value: value for value in calls]
    os.write(master, (text + "\r").encode())
    deadline = time.monotonic() + 40
    while time.monotonic() < deadline:
        pump()
        if events.exists() and len(events.read_text().splitlines()) > previous:
            pump(0.4)
            return
    raise AssertionError("Pi did not settle:\n" + "\n".join(screen.display))


def capture(name):
    lines = list(screen.display)
    (out / f"todo-{name}.txt").write_text("\n".join(lines) + "\n")
    headings = [i for i, line in enumerate(lines) if "Tâches (" in line]
    assert headings, lines
    return lines[headings[-1] :]


try:
    resize(100, 40)
    pump(2)
    assert b"[Extension issues]" not in raw, raw.decode(errors="replace")
    prompt(
        "Track this work",
        call(
            "todo",
            op="init",
            items=[
                {"text": "Research", "activeForm": "checking the implementation"},
                "Build",
                "Verify",
            ],
        ),
    )
    short = capture("short")
    assert any(
        "Research" in row and "checking the implementation" in row for row in short
    ), short
    prompt(
        "Track a long list",
        call("todo", op="init", items=[f"Task {i}" for i in range(1, 13)]),
        call("todo", op="done", id=1),
        call("todo", op="start", id=12),
    )
    compact = capture("compact")
    assert any("Task 12" in row for row in compact), compact
    assert any("autres" in row for row in compact), compact
    os.write(master, b"\x1b[116;6u")
    pump(0.5)
    collapsed = capture("collapsed")
    assert any("ctrl+shift+t pour développer" in row for row in collapsed), collapsed
    assert not any("Task 12" in row for row in collapsed), collapsed
    resize(70, 30)
    pump(0.5)
    capture("narrow")
    os.write(master, b"\x0f")
    pump(0.5)
    expanded = capture("expanded")
    assert sum("Task " in row for row in expanded) == 12, expanded
    assert any("Task 12" in row for row in expanded), expanded
    assert b"Extension shortcut conflict" not in raw
    print(
        "PASS todo real TUI: managed skin, French labels, activity, active-tail visibility, collapse, resize and native expansion",
        flush=True,
    )
finally:
    (out / "todo-ui.ansi").write_bytes(raw)
    try:
        os.kill(pid, signal.SIGTERM)
        os.waitpid(pid, 0)
    except ProcessLookupError:
        pass
    os.close(master)
    scripted.stop()
