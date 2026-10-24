"""Real Pi in RPC mode with the checkpoint extension: snapshots, /undo, /redo and the restore dialog.

  checkpoint-session.py PI EXTENSION OUTPUT

The model is scripted on loopback. The project is a real git repository; the extension runs against real git.
"""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, os.path.dirname(__file__))
from scripted_pi import Rpc, call  # noqa: E402

pi, extension, output = sys.argv[1:]
Path(output).mkdir(parents=True, exist_ok=True)
FILES = {"a.txt": "original a\n", "sub/b.txt": "original b\n", ".gitignore": "*.log\n"}


def init_repo(project, _agent):
    identity = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}
    for args in (["init", "-q", "-b", "main"], ["add", "-A"], ["commit", "-qm", "init"]):
        subprocess.run(["git", *args], cwd=project, check=True, capture_output=True, env={**os.environ, **identity})


def entries(session):
    return [json.loads(line) for line in Path(session).read_text().splitlines() if line.startswith("{")]


def checkpoints(session):
    return [e for e in entries(session) if e.get("type") == "custom" and e.get("customType") == "checkpoint"]


def main():
    session = Path(tempfile.mkdtemp(prefix="pi-checkpoint-session-")) / "session.jsonl"
    rpc = Rpc(pi, "checkpoints", [extension], FILES, session=session, before=init_repo)
    project = rpc.project
    try:
        # A turn that edits, creates and deletes.
        rpc.prompt(
            "Reorganise the notes",
            [
                lambda r, p: call("write", path="created.txt", content="new\n"),
                lambda r, p: call("edit", path="a.txt", oldText="original a", newText="agent edit"),
                lambda r, p: call("bash", command="rm sub/b.txt"),
            ],
        )
        assert (project / "created.txt").exists() and not (project / "sub/b.txt").exists()
        assert (project / "a.txt").read_text() == "agent edit\n"
        found = checkpoints(session)
        assert len(found) == 1, found
        assert found[0]["data"]["prompt"] == "Reorganise the notes" and len(found[0]["data"]["commit"]) == 40, found[0]
        everything = entries(session)
        at = next(i for i, e in enumerate(everything) if e.get("customType") == "checkpoint")
        # Pi persists the prompt and tool declarations as a system message just before the first user message.
        following = next(e for e in everything[at + 1 :] if e["type"] == "message" and e["message"]["role"] != "system")
        assert following["message"]["role"] == "user", following
        print("PASS snapshot: one checkpoint entry, written before the prompt it precedes", flush=True)

        # /undo restores the files and rewinds the conversation.
        messages_before = len(rpc.command(type="get_messages")["messages"])
        assert messages_before >= 5, messages_before
        rpc.prompt("/undo")
        rpc.wait_notification("Undid the last turn")
        dialog = rpc.dialogs[-1]
        assert dialog["method"] == "confirm" and dialog["title"] == "Undo the last turn?", dialog
        for line in ("↺ revert  a.txt", "+ restore sub/b.txt", "− remove  created.txt"):
            assert line in dialog["message"], (line, dialog["message"])
        assert (project / "a.txt").read_text() == "original a\n"
        assert (project / "sub/b.txt").read_text() == "original b\n"
        assert not (project / "created.txt").exists()
        conversation = [m for m in rpc.command(type="get_messages")["messages"] if m.get("role") != "system"]
        assert conversation == [], "the conversation returned to before the prompt: " + json.dumps(conversation)[:300]
        print("PASS undo: files restored (edit reverted, creation removed, deletion undone) and the conversation rewound", flush=True)

        # /redo brings both back.
        rpc.notifications.clear()
        rpc.prompt("/redo")
        rpc.wait_notification("Redone")
        assert (project / "a.txt").read_text() == "agent edit\n"
        assert (project / "created.txt").read_text() == "new\n"
        assert not (project / "sub/b.txt").exists()
        assert len(rpc.command(type="get_messages")["messages"]) == messages_before
        print("PASS redo: the agent's changes and the conversation are back", flush=True)

        # Declining the dialog changes nothing.
        rpc.answer = lambda request: False
        asked = len(rpc.dialogs)
        rpc.prompt("/undo")
        rpc.wait_dialog(asked)
        rpc.pump(1.5)
        assert (project / "created.txt").exists() and len(rpc.command(type="get_messages")["messages"]) == messages_before
        print("PASS decline: answering no leaves the files and the conversation alone", flush=True)

        # A nothing-to-undo session says so.
        rpc.answer = lambda request: True
    finally:
        rpc.close()

    fresh = Rpc(pi, "checkpoints-empty", [extension], FILES, before=init_repo)
    try:
        fresh.prompt("/undo")
        fresh.wait_notification("Nothing to undo")
        print("PASS empty: /undo before any message says there is nothing to undo", flush=True)
    finally:
        fresh.close()
    (Path(output) / "session.jsonl").write_text(Path(session).read_text())


main()
print("PASS: real Pi with checkpoints", flush=True)
