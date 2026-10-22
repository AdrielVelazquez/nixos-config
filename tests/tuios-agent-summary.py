import json
from pathlib import Path
import re
import subprocess
import sys


filter_path = Path(sys.argv[1])
dock_widths = [int(value) for value in sys.argv[2:]]
assert dock_widths and all(1 <= width <= 80 for width in dock_widths), "configured widths must not trigger TUIOS's 24-column fallback"


def render(payload):
    result = subprocess.run(
        ["jq", "-r", "-f", str(filter_path)],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        check=True,
    )
    assert result.stdout.endswith("\n") and result.stdout.count("\n") == 1, "emit exactly one newline-terminated dock line"
    return result.stdout[:-1]


def plain(text):
    return re.sub(r"\x1b\[[0-9;]*m", "", text)


working = render({"agents": [{"state": "working"}] * 2})
assert working == "\x1b[38;2;0;164;255m ◐ 2 working \x1b[0m", "pad both sides inside each colored group"

states = ["idle", "done", "working", "unknown", "errored", "needs_input", "needs_input"]
output = render({"agents": [{"state": state} for state in states]})
assert plain(output) == " ! 2 needs you  × 1 errored  ◐ 1 working  ○ 1 idle  ✓ 1 done  □ 1 unknown ", output

# Each full group has its own foreground, followed by a reset before separators.
expected_groups = [
    ("255;152;90", " ! 2 needs you "),
    ("255;56;139", " × 1 errored "),
    ("0;164;255", " ◐ 1 working "),
    ("133;131;146", " ○ 1 idle "),
    ("0;255;178", " ✓ 1 done "),
    ("133;131;146", " □ 1 unknown "),
]
assert output == "".join(f"\x1b[38;2;{rgb}m{text}\x1b[0m" for rgb, text in expected_groups), repr(output)

pair = render({"agents": [{"state": "working"}, {"state": "idle"}]})
assert pair == "\x1b[38;2;0;164;255m ◐ 1 working \x1b[0m · \x1b[38;2;133;131;146m ○ 1 idle \x1b[0m", "keep roomy, uncolored separators when they fit"

assert render({"agents": []}) == "", "no agents must leave the cell empty"
assert render({}) == "", "absent agent list must leave the cell empty"
assert render({"agents": None}) == "", "null agent list must leave the cell empty"
assert plain(render({"agents": [{"state": "working"}] * 12})) == " ◐ 12 working ", "hide zero states and retain multi-digit counts"
assert render({"agents": [{"state": "none"}, {"state": "future-state"}]}) == "", "do not invent counts for unrecognized states"
assert render({"agents": [{}]}) == "", "an agent without a state must not invent a group"

all_states = ["needs_input", "errored", "working", "idle", "done", "unknown"]
two_digit_counts = render({"agents": [{"state": state} for state in all_states for _ in range(12)]})
assert plain(two_digit_counts) == " ! 12 needs you  × 12 errored  ◐ 12 working  ○ 12 idle  ✓ 12 done  □ 12 unknown "
assert len(plain(two_digit_counts)) <= min(dock_widths), "all two-digit groups must fit each installed dock width cap"

malformed = subprocess.run(
    ["jq", "-r", "-f", str(filter_path)],
    input="{",
    capture_output=True,
    text=True,
)
assert malformed.returncode != 0 and not malformed.stdout, "invalid JSON must not display a misleading summary"
print("TUIOS agent summary: padding, colored groups, resets, counts, priority, and empty states passed")
