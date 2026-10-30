"""Real Pi todo: nested persistence, errors, metadata and session lifecycle on loopback."""

import json
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
from scripted_pi import Rpc, call, run

pi, fixture_file, output, *flags = sys.argv[1:]
fixture = json.loads(Path(fixture_file).read_text())
out = Path(output)
out.mkdir(parents=True, exist_ok=True)
entry = fixture["todoEntry"]


def steps(*calls):
    return [lambda results, project, value=value: value for value in calls]


def results(events, name="todo"):
    return [
        event
        for event in events
        if event.get("type") == "tool_execution_end" and event.get("toolName") == name
    ]


def nested(tool="codemode"):
    session = Path(tempfile.mkdtemp(prefix="pi-todo-nested-")) / "session.jsonl"
    if tool == "codemode":
        extensions = [entry]
        code = 'return await tools.todo({op:"init",items:["Persist nested work","Verify it"]});'
    else:
        extensions = [entry, fixture["evalEntry"]]
        code = 'print(tool.todo(op="init", items=["Persist nested work", "Verify it"]))\ntry:\n    tool.todo(op="done", id=999)\nexcept Exception as error:\n    print(type(error).__name__)'
    first = run(
        pi,
        f"todo-{tool}",
        extensions,
        {},
        steps(call(tool, code=code)),
        settings={"defaultTools": ["+codemode"]},
        session=session,
        out=out,
    )
    if tool == "eval":
        assert "ToolError" in first.results[0], first.results
    entries = [json.loads(line) for line in session.read_text().splitlines()]
    assert any(e.get("customType") == "pi-todo-state" for e in entries), (
        "nested todo mutation must persist a custom snapshot"
    )
    resumed = run(
        pi,
        f"todo-{tool}-resumed",
        [entry],
        {},
        steps(call("todo", op="view")),
        session=session,
        out=out,
    )
    state = results(resumed.events)[0]["result"]["details"]
    assert [t["text"] for t in state["todos"]] == [
        "Persist nested work",
        "Verify it",
    ], state
    print(
        f"PASS todo {tool}: nested mutation persists across a new Pi process",
        flush=True,
    )


def richer_tasks():
    scripted = run(
        pi,
        "todo-features",
        [entry],
        {},
        steps(
            call(
                "todo",
                op="init",
                items=[
                    "Research",
                    {
                        "text": "Build",
                        "description": "Long detail",
                        "owner": "Ada",
                        "blockedBy": [1],
                    },
                ],
            ),
            call(
                "todo",
                op="update",
                id=2,
                text="Implement",
                activeForm="implementing",
                metadata={"priority": 1},
            ),
            call("todo", op="get", id=2),
            call("todo", op="view", owner="Ada"),
            call("todo", op="update", id=1, addBlockedBy=[2]),
            call("todo", op="remove", id=1),
            call("todo", op="done", id=99),
            call("todo", op="block", id=1, reason="Needs access"),
            call("todo", op="view"),
            call("todo", op="update", id=2, owner=None),
        ),
        out=out,
    )
    events = results(scripted.events)
    assert len(events) == 10
    assert "Long detail" in scripted.results[2]
    assert "Implement" in scripted.results[3] and "Research" not in scripted.results[3]
    assert len(events[3]["result"]["details"]["todos"]) == 2
    assert all(events[i]["isError"] for i in [4, 5, 6]), events
    final = events[-1]["result"]["details"]
    assert final["todos"][0]["reason"] == "Needs access"
    assert final["todos"][1]["status"] == "in_progress"
    assert final["todos"][1]["metadata"] == {"priority": 1}
    assert not events[-1]["isError"]
    assert "owner" not in final["todos"][1]
    print(
        "PASS todo rich tasks: editable fields, filtered reads, cycle/removal errors and manual blockers",
        flush=True,
    )


def lifecycle():
    probe = Path(tempfile.mkdtemp(prefix="pi-todo-probe-")) / "probe.ts"
    probe.write_text("""export default pi => {
      pi.registerCommand("todo-test-reload", {handler: async (_,ctx) => {await ctx.reload();}});
      pi.registerCommand("todo-test-tree", {handler: async (id,ctx) => {await ctx.navigateTree(id.trim(), {summarize:false});}});
    };""")
    session = probe.parent / "session.jsonl"
    rpc = Rpc(
        pi,
        "todo-lifecycle",
        [entry, str(probe)],
        {},
        session=session,
        settings={
            "compaction": {
                "enabled": False,
                "keepRecentTokens": 32,
                "reserveTokens": 256,
            }
        },
    )
    try:

        def prompt(text, *calls):
            rpc.prompt(text, steps(*calls))
            rpc.wait(lambda e: e.get("type") == "agent_settled", what="todo settlement")

        prompt("Create tasks", call("todo", op="init", items=["First", "Second"]))
        entries = rpc.command(type="get_entries")["entries"]
        first = next(e["id"] for e in entries if e.get("customType") == "pi-todo-state")
        prompt("Complete first", call("todo", op="done", id=1))
        rpc.prompt("/todos in_progress Second")
        assert (
            "Second" in rpc.notifications[-1] and "First" not in rpc.notifications[-1]
        ), rpc.notifications
        rpc.prompt("/todo-test-reload")
        prompt("Read after reload", call("todo", op="view"))
        assert (
            results(rpc.records)[-1]["result"]["details"]["todos"][0]["status"]
            == "done"
        )
        rpc.prompt("/todo-test-tree " + first)
        prompt("Read after tree", call("todo", op="view"))
        assert (
            results(rpc.records)[-1]["result"]["details"]["todos"][0]["status"]
            == "in_progress"
        )
        rpc.scripted.steps = []
        rpc.command(
            type="compact", customInstructions="Briefly summarize this isolated test."
        )
        prompt("Read after compact", call("todo", op="view"))
        assert len(results(rpc.records)[-1]["result"]["details"]["todos"]) == 2
        rpc.command(type="new_session")
        prompt("A fresh session", call("todo", op="view"))
        assert results(rpc.records)[-1]["result"]["details"]["todos"] == []
        assert not rpc.stderr, rpc.stderr
        print(
            "PASS todo lifecycle: slash filters, reload, branch navigation, compaction and new-session isolation",
            flush=True,
        )
    finally:
        (out / "todo-lifecycle-events.json").write_text(
            json.dumps(rpc.records, indent=2)
        )
        rpc.close()


nested()
if "--nested-only" not in flags:
    nested("eval")
    richer_tasks()
    lifecycle()
