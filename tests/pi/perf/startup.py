"""Pi start-up cost: wall time to a `get_state` answer in RPC mode, CPU time and resident memory, for no extensions, each
managed extension on its own, and the whole set. Usage: startup.py [--runs N] [--only SUBSTR]... [--json FILE].
Runs in a throwaway HOME and agent directory against the live settings' extension list; nothing real is touched."""
import argparse, json, os, shutil, statistics, subprocess, sys, tempfile, threading, time
from pathlib import Path

def _package_binary() -> str:
    """Pi itself, not the `pi` on PATH: that one is the Headroom launcher, which starts a proxy before Pi runs."""
    if os.environ.get("PI_TEST_PACKAGE_DIR"): return str(Path(os.environ["PI_TEST_PACKAGE_DIR"]).parents[1] / "bin" / "pi")
    found = sorted(Path("/nix/store").glob("*-pi-coding-agent-*/bin/pi"))
    if not found: sys.exit("no Pi package binary; set PI_BIN or PI_TEST_PACKAGE_DIR")
    return str(found[-1])


PI = os.environ.get("PI_BIN") or _package_binary()
parser = argparse.ArgumentParser()
parser.add_argument("--runs", type=int, default=5)
parser.add_argument("--only", action="append", default=[], help="measure only extensions whose path contains this")
parser.add_argument("--json", help="write the results here")
parser.add_argument("--settings", default=os.path.expanduser("~/.pi/agent/settings.json"))
parser.add_argument("--cold", action="store_true", help="give every run an empty TMPDIR, so jiti's compile cache starts cold (default: one shared, warmed by an untimed run, as in daily use)")
parser.add_argument("--launcher", action="store_true", help="also time the managed `pi` command (Headroom launcher, real config; it starts MCP servers and the proxy)")
parser.add_argument("--skip", action="append", default=["extensions/headroom.ts"], help="never load these (default: Headroom, which starts a proxy)")
args = parser.parse_args()

live = json.load(open(args.settings))
exts = [e for e in live["extensions"] if not any(s in e for s in args.skip)]
short = lambda e: (e.split("/nix/store/")[-1][33:] if "/nix/store/" in e else e).split("/node_modules/")[0]
base = {k: v for k, v in live.items() if k not in ("packages", "skills", "prompts", "extensions", "defaultProvider", "defaultModel", "subagents")}
base["retry"] = {"enabled": False}; base["compaction"] = {"enabled": False}


SHARED_TMP = Path(tempfile.mkdtemp(prefix="perf-jiti-"))


def measure(extensions: list[str] | None, launcher: bool = False) -> dict:
    root = Path(tempfile.mkdtemp(prefix="perf-"))
    home, agent, project = root / "home", root / "agent", root / "project"
    for d in (home, agent, project): d.mkdir()
    if not launcher: (agent / "settings.json").write_text(json.dumps({**base, "extensions": extensions}))
    env = {"PATH": os.environ["PATH"], "HOME": str(home), "TMPDIR": str(root if args.cold else SHARED_TMP), "XDG_CACHE_HOME": str(home / "cache"), "XDG_CONFIG_HOME": str(home / "config"),
           "XDG_DATA_HOME": str(home / "data"), "XDG_STATE_HOME": str(home / "state"), "PI_CODING_AGENT_DIR": str(agent), "PI_OFFLINE": "1", "PI_TELEMETRY": "0", "LANG": "C.UTF-8"}
    if launcher:
        env = {k: v for k, v in os.environ.items() if k != "PI_CODING_AGENT_DIR"} | {"HOME": os.environ["HOME"], "PI_TELEMETRY": "0"}
    t0 = time.perf_counter()
    proc = subprocess.Popen([shutil.which("pi") if launcher else PI, "--mode", "rpc", "--offline", "--no-approve", "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-mcp", "--no-session"],
                            cwd=project, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    proc.stdin.write('{"id":"1","type":"get_state"}\n'); proc.stdin.flush()
    threading.Timer(25, proc.kill).start()  # a hung start-up is a result, not a reason to wait forever
    ok = False
    for line in proc.stdout:
        if '"id":"1"' in line and '"type":"response"' in line:
            ok = '"success":true' in line; break
    wall = time.perf_counter() - t0
    rss = cpu = 0.0
    try:
        rss = int(next(l for l in open(f"/proc/{proc.pid}/status") if l.startswith("VmRSS")).split()[1]) / 1024
        fields = open(f"/proc/{proc.pid}/stat").read().rsplit(")", 1)[1].split()
        cpu = (int(fields[11]) + int(fields[12])) / os.sysconf("SC_CLK_TCK")
    except (OSError, StopIteration): pass
    proc.kill(); proc.wait(); shutil.rmtree(root, ignore_errors=True)
    return {"ok": ok, "wall": wall, "cpu": cpu, "rss": rss}


def summarize(label: str, extensions: list[str] | None, launcher: bool = False) -> dict:
    if not args.cold and not launcher: measure(extensions, launcher)  # warms jiti's compile cache; not counted
    runs = [measure(extensions, launcher) for _ in range(args.runs)]
    good = [r for r in runs if r["ok"]]
    row = {"label": label, "ok": len(good) == len(runs)}
    for key in ("wall", "cpu", "rss"): row[key] = statistics.median(r[key] for r in (good or runs))
    return row


def show(r: dict) -> None:
    print(f"{r['label'][:58]:58} {r['wall']:7.2f} {r['wall'] - zero['wall']:+7.2f} {r['cpu']:6.2f} {r['rss']:7.0f} {r['rss'] - zero['rss']:+6.0f}{'' if r['ok'] else '  (did not answer)'}", flush=True)


results = [summarize("(no extensions)", [])]
zero = results[0]
print(f"{'extension':58} {'wall s':>7} {'+wall':>7} {'cpu s':>6} {'rss MB':>7} {'+rss':>6}")
show(zero)
for e in exts:
    if args.only and not any(o in e for o in args.only): continue
    results.append(summarize(short(e), [e])); show(results[-1])
if not args.only:
    # An extension that cannot start on its own (required-integrations wants Headroom) would sink the whole set.
    usable = [e for e, r in zip([x for x in exts], results[1:]) if r["ok"]]
    results.append(summarize(f"ALL {len(usable)} that start without Headroom", usable)); show(results[-1])
if args.launcher: results.append(summarize("managed `pi` launcher (Headroom + everything)", None, True)); show(results[-1])
if args.json: Path(args.json).write_text(json.dumps(results, indent=1))
