"""Real Pi, real formatter: a file a bash command writes is named to the model and formatted; a command that writes nothing
adds nothing; a failed command reports its writes but is not formatted.

  bash-format-session.py PI FIXTURE OUTPUT      (FIXTURE is the JSON with `formatEntry`)
"""

import json
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(__file__))
from scripted_pi import call, run  # noqa: E402

pi, fixture_file, output = sys.argv[1:]
entry = json.loads(Path(fixture_file).read_text())["formatEntry"]
SOURCE = "package main\nfunc main(){\nx:=1\n_ = x\n}\n"


def repo(project, _agent):
    commit = ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "init"]
    for args in (["init", "-q", "-b", "main"], ["add", "-A"], commit):
        subprocess.run(["git", *args], cwd=project, check=True, capture_output=True)


steps = [
    lambda r, p: call("bash", command=f"cat > main.go <<'E'\n{SOURCE}E"),
    lambda r, p: call("bash", command="ls"),
    lambda r, p: call("bash", command=f"printf 'package bad\\nfunc f(){{}}\\n' > bad.go; exit 3"),
]
session = run(
    pi, "bash-format", [entry], {"go.mod": "module example.com/fixture\n\ngo 1.26\n", "README.md": "hi\n"}, steps,
    before=repo, out=output,
)  # fmt: skip
wrote, listed, failed = session.results[:3]
project = Path(session.project)

assert "This command changed 1 file: main.go." in wrote, wrote
assert "Formatted main.go with" in wrote, wrote
formatted = (project / "main.go").read_text()
assert formatted != SOURCE and "x := 1" in formatted, formatted
assert "This command changed" not in listed and "Formatted" not in listed, listed
assert "This command changed 1 file: bad.go." in failed and "Formatted" not in failed, failed
assert (project / "bad.go").read_text() == "package bad\nfunc f(){}\n", "a failed command's file is left as written"
print("PASS: a heredoc-written Go file was named and formatted; ls added nothing; a failed command was reported and not formatted")
