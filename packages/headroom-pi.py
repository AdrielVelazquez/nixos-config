#!/usr/bin/env python3
"""Session-owned, loopback-only Headroom lifecycle for Pi (Linux).

Only this launcher's private registry is reusable. Never adopt an arbitrary
healthy listener. Native child sessions and async-run reservations hold leases
so the proxy can outlive a foreground UI without becoming a resident service.
"""
import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import sys
import time
import urllib.request
import uuid


def identity(pid):
    try:
        fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
        return fields[19] if fields[0] != "Z" else None
    except (OSError, IndexError):
        return None


def alive(pid, started):
    return isinstance(pid, int) and pid > 0 and started is not None and identity(pid) == started


def private_dir(path):
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = path.lstat()
    if path.is_symlink() or not path.is_dir() or info.st_uid != os.getuid():
        raise RuntimeError("Headroom/Pi state directory is not privately owned")
    path.chmod(0o700)


@contextmanager
def locked(root):
    fd = os.open(root / "lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        os.close(fd)


def write_json(path, value):
    temporary = path.with_name(".tmp-" + str(uuid.uuid4()))
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "w") as file:
            json.dump(value, file)
            file.flush()
            os.fsync(file.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def read_json(path, default=None):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        return default
    with os.fdopen(fd) as file:
        info = os.fstat(file.fileno())
        if info.st_uid != os.getuid() or info.st_size > 2 * 1024 * 1024:
            raise RuntimeError("Invalid Headroom/Pi state file")
        return json.load(file)


def project_root(cwd, git="git"):
    result = subprocess.run([git, "-C", str(cwd), "rev-parse", "--show-toplevel"],
                            capture_output=True, text=True)
    # A worktree is the workspace being edited, not its common Git directory's
    # main checkout. Keep its graph and any existing memory store local to it.
    return Path(result.stdout.strip()).resolve() if result.returncode == 0 else cwd.resolve()


def memory_path(project):
    # Match upstream's current project-key layout, retaining a legacy DB when
    # it is the only existing store. Never move, merge, truncate or delete it.
    folder = project / ".headroom"
    name = re.sub(r"[^A-Za-z0-9._-]+", "-", project.name).strip("-._")[:64] or "project"
    digest = hashlib.sha256(str(project).encode()).hexdigest()[:16]
    current = folder / "memories/projects" / f"{name}-{digest}" / "memory.db"
    legacy = folder / "memory.db"
    return current if current.exists() or not legacy.exists() else legacy


def healthy(port):
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=0.5) as response:
            return response.status == 200
    except Exception:
        return False


def owns_listener(pid, port):
    try:
        sockets = {os.readlink(fd)[8:-1] for fd in Path(f"/proc/{pid}/fd").iterdir()
                   if os.readlink(fd).startswith("socket:[")}
        for file in ["/proc/net/tcp", "/proc/net/tcp6"]:
            for line in Path(file).read_text().splitlines()[1:]:
                fields = line.split()
                if len(fields) > 9 and fields[3] == "0A" and int(fields[1].split(":")[1], 16) == port and fields[9] in sockets:
                    return True
    except (OSError, ValueError):
        pass
    return False


def choose_port(preferred):
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", preferred))
        return probe.getsockname()[1]


def active_leases(root, state):
    count = 0
    for path in (root / "leases").glob("*.json"):
        if not re.fullmatch(r"[0-9a-f-]{36}\.json", path.name):
            continue
        try:
            lease = read_json(path, {})
            keep = lease.get("instance") == state["instance"]
            if lease.get("kind") == "run" and keep:
                status = read_json(Path(lease["statePath"]), {})
                terminal = status.get("state") in ["complete", "failed", "stopped", "partial", "rejected"]
                keep = not terminal and (alive(status.get("pid"), lease.get("started") or identity(status.get("pid")))
                                         or time.time() * 1000 < lease.get("deadline", 0))
            else:
                keep = keep and alive(lease.get("pid"), lease.get("started"))
        except (OSError, ValueError, KeyError, TypeError):
            keep = False
        if keep:
            count += 1
        else:
            path.unlink(missing_ok=True)
    return count


def stop_proxy(pid, started):
    if not alive(pid, started):
        return
    try:
        os.killpg(pid, signal.SIGTERM)
        deadline = time.monotonic() + 5
        while alive(pid, started) and time.monotonic() < deadline:
            time.sleep(0.05)
        if alive(pid, started):
            os.killpg(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def manage(root, config):
    # The creator holds this lock until both state and its initial lease exist.
    with locked(root):
        state = read_json(root / "state.json")
    proxy = None
    try:
        pid, started, port = state.get("proxyPid"), state.get("proxyStarted"), state.get("port")
        adopt = alive(pid, started) and isinstance(port, int) and owns_listener(pid, port) and healthy(port)
        if not adopt:
            port = choose_port(config.get("port", 0))
            # The packaged Headroom command supplies its own Python closure.
            # Inherited paths/home can corrupt even that interpreter's bootstrap.
            env = {key: value for key, value in os.environ.items() if key not in ["PYTHONPATH", "PYTHONHOME"]}
            for key, value in config.get("tuningEnv", {}).items():
                env.setdefault(key, str(value))
            env["HEADROOM_ALLOWED_BASE_URLS"] = ",".join(config.get("upstreamOrigins", []))
            env["HEADROOM_LOG_MESSAGES"] = "0"
            env["PATH"] = os.pathsep.join(config.get("extraPath", []) + [env.get("PATH", "")])
            command = config["proxyCommand"] + ["proxy", "--host", "127.0.0.1", "--port", str(port), "--workers", "1"]
            if config.get("memory"):
                # Native MCP exclusively owns memory. Merely disabling proxy
                # tool injection leaves its response interceptor capable of
                # executing unadvertised memory calls outside Pi's ceilings.
                command += ["--no-memory-tools"]
            if config.get("codeGraph"):
                command += ["--code-graph"]
            proxy = subprocess.Popen(command, cwd=state["project"], env=env, stdin=subprocess.DEVNULL,
                                     start_new_session=True)
            pid, started = proxy.pid, identity(proxy.pid)
            deadline = time.monotonic() + config.get("startupTimeout", 60)
            while time.monotonic() < deadline:
                if proxy.poll() is not None:
                    raise RuntimeError(f"Headroom exited during startup ({proxy.returncode})")
                if owns_listener(pid, port) and healthy(port):
                    break
                time.sleep(0.05)
            else:
                raise RuntimeError("Headroom startup timed out")
        with locked(root):
            state.update(ready=True, port=port, proxyPid=pid, proxyStarted=started)
            write_json(root / "state.json", state)
        while alive(pid, started):
            with locked(root):
                if active_leases(root, state) == 0:
                    state["stopping"] = True
                    write_json(root / "state.json", state)
                    break
            time.sleep(0.2)
    except Exception as error:
        state["error"] = str(error)
    finally:
        stop_proxy(proxy.pid if proxy else state.get("proxyPid"), started if proxy else state.get("proxyStarted"))
        if proxy:
            try:
                proxy.wait(timeout=2)
            except subprocess.TimeoutExpired:
                pass
        with locked(root):
            state.update(ready=False, stopping=True)
            write_json(root / "state.json", state)


def acquire(config_path, pid=None):
    """Acquire an owned process lease, also for native clients that re-exec themselves."""
    config = json.loads(config_path.read_text())
    if config.get("version") != 1:
        raise RuntimeError("Unsupported Headroom/Pi configuration version")
    client = config.get("client", "pi")
    if client not in ["pi", "omp"]:
        raise RuntimeError("Unsupported Headroom client namespace")
    owner = os.getpid() if pid is None else pid
    started = identity(owner)
    if not alive(owner, started) or Path(f"/proc/{owner}").stat().st_uid != os.getuid():
        raise RuntimeError("Headroom lease requires a live same-user process")
    cwd = Path.cwd().resolve()
    project = project_root(cwd, config.get("gitCommand", "git"))
    database = memory_path(project)
    if config.get("memory"):
        # Both the proxy and standalone memory MCP open this exact store.
        # Creating a new parent is safe; existing files/permissions stay intact.
        database.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    tuning = {key: os.environ.get(key, str(value)) for key, value in config.get("tuningEnv", {}).items()}
    signature = hashlib.sha256(json.dumps([str(cwd), config, tuning], sort_keys=True).encode()).hexdigest()
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR") or os.environ.get("TMPDIR") or "/tmp/opencode")
    base = runtime / f"headroom-{client}-{os.getuid()}"
    private_dir(base)
    root = base / signature
    private_dir(root); private_dir(root / "leases")
    token = str(uuid.uuid4() if pid is None else uuid.uuid5(uuid.NAMESPACE_URL, f"{root}:{owner}:{started}"))
    lease_path = root / "leases" / (token + ".json")
    deadline = time.monotonic() + config.get("startupTimeout", 60) + 3
    while True:
        with locked(root):
            state = read_json(root / "state.json", {})
            owner_alive = alive(state.get("managerPid"), state.get("managerStarted"))
            if not owner_alive or not state.get("stopping"):
                if not owner_alive:
                    adopted = alive(state.get("proxyPid"), state.get("proxyStarted")) and healthy(state.get("port"))
                    state = {**state, "instance": state.get("instance") if adopted else str(uuid.uuid4()),
                             "signature": signature, "cwd": str(cwd), "project": str(project),
                             "memoryDB": str(database), "ready": False, "stopping": False}
                    state.pop("error", None)
                    log = os.open(root / "proxy.log", os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW, 0o600)
                    try:
                        manager = subprocess.Popen([sys.executable, "-E", str(Path(__file__).resolve()), "--manager", str(root), "--config", str(config_path)],
                                                   stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
                    finally:
                        os.close(log)
                    state.update(managerPid=manager.pid, managerStarted=identity(manager.pid))
                    write_json(root / "state.json", state)
                write_json(lease_path, {"instance": state["instance"], "kind": "process", "pid": owner, "started": started})
                break
        if time.monotonic() > deadline:
            raise RuntimeError("Headroom is still shutting down; retry")
        time.sleep(0.05)
    try:
        while time.monotonic() < deadline:
            state = read_json(root / "state.json", {})
            if state.get("ready") and not state.get("stopping") and alive(state.get("managerPid"), state.get("managerStarted")):
                break
            if state.get("error") or not alive(state.get("managerPid"), state.get("managerStarted")):
                raise RuntimeError(state.get("error") or "Headroom manager exited")
            time.sleep(0.05)
        else:
            raise RuntimeError("Headroom startup timed out")
        return config, {"proxyURL": f"http://127.0.0.1:{state['port']}", "stateDir": str(root),
                        "instance": state["instance"], "memoryDB": state["memoryDB"],
                        "project": state["project"], "leasePath": str(lease_path)}
    except BaseException:
        lease_path.unlink(missing_ok=True)
        raise


def client_environment(config_path, config, acquired):
    child_env = {key: value for key, value in os.environ.items() if key not in ["PYTHONPATH", "PYTHONHOME"]}
    prefix = "HEADROOM_" + config.get("client", "pi").upper()
    child_env["HEADROOM_PROXY_URL"] = acquired["proxyURL"]
    for key, value in {"STATE_DIR": acquired["stateDir"], "INSTANCE": acquired["instance"],
                       "MEMORY_DB": acquired["memoryDB"], "PROJECT": acquired["project"],
                       "CONFIG": str(config_path)}.items():
        child_env[prefix + "_" + key] = value
    if config.get("client", "pi") == "pi":
        if not child_env.get("PI_SUBAGENTS_TEMP_ROOT"):
            runtime = Path(os.environ.get("XDG_RUNTIME_DIR") or os.environ.get("TMPDIR") or "/tmp/opencode")
            async_root = runtime / f"pi-subagents-{os.getuid()}"
            private_dir(async_root)
            child_env["PI_SUBAGENTS_TEMP_ROOT"] = str(async_root)
    for adapter in config.get("adapters", []):
        child_env[adapter["urlEnv"]] = acquired["proxyURL"]
        child_env[adapter["requiredEnv"]] = "1"
    return child_env


def launch(config_path, args):
    config = json.loads(config_path.read_text())
    if config.get("version") != 1:
        raise RuntimeError("Unsupported Headroom/Pi configuration version")
    if args in [["--help"], ["-h"], ["--version"], ["-v"]]:
        env = {key: value for key, value in os.environ.items() if key not in ["PYTHONPATH", "PYTHONHOME"]}
        return subprocess.call(config["piCommand"] + args, env=env)
    config, acquired = acquire(config_path)
    try:
        child_env = client_environment(config_path, config, acquired)
        child = subprocess.Popen(config["piCommand"] + args, env=child_env)
        def forward(signum, _frame):
            if child.poll() is None and signum != signal.SIGINT:
                child.send_signal(signum)
        for signum in [signal.SIGTERM, signal.SIGHUP, signal.SIGINT]:
            signal.signal(signum, forward)
        result = child.wait()
        return result if result >= 0 else 128 - result
    finally:
        Path(acquired["leasePath"]).unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--manager", type=Path)
    parser.add_argument("--acquire", type=int)
    parser.add_argument("args", nargs=argparse.REMAINDER)
    options = parser.parse_args()
    if options.manager:
        manage(options.manager, json.loads(options.config.read_text()))
        return 0
    args = options.args[1:] if options.args[:1] == ["--"] else options.args
    try:
        if options.acquire is not None:
            _config, acquired = acquire(options.config.resolve(), options.acquire)
            print(json.dumps(acquired))
            return 0
        return launch(options.config.resolve(), args)
    except Exception as error:
        print(f"Pi requires Headroom: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
