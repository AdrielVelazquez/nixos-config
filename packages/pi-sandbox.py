import argparse
import fcntl
import hashlib
import json
import os
import re
import signal
import stat
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path


class Terminated(BaseException):
    def __init__(self, number):
        self.number = number


def parse_options(arguments):
    parser = argparse.ArgumentParser(
        description="Run managed Pi in a local microVM; ordinary pi is unchanged.",
        allow_abbrev=False,
    )
    parser.add_argument("--config", help=argparse.SUPPRESS)
    parser.add_argument(
        "--project", default=os.getcwd(), help="Git project to share writable"
    )
    parser.add_argument("--repo-ro", action="append", default=[], metavar="PATH")
    parser.add_argument("--repo-rw", action="append", default=[], metavar="PATH")
    parser.add_argument(
        "--diagnose", action="store_true", help="Print policy without starting a VM"
    )
    if "--" in arguments:
        separator = arguments.index("--")
        return parser.parse_args(arguments[:separator]), arguments[separator + 1 :]
    return parser.parse_args(arguments), []


def validate_host_path(path, home, state_root, protected_paths=()):
    path = Path(path).expanduser().resolve(strict=True)
    home = Path(home).resolve()
    state_root = Path(state_root).resolve()
    if not path.is_dir():
        raise ValueError("Shared projects must be directories")
    if home.is_relative_to(path):
        raise ValueError(
            "Refusing to expose the host home or one of its parent directories"
        )
    sensitive = [
        home / name for name in (".ssh", ".aws", ".gnupg", ".pi", ".config", ".local")
    ]
    sensitive.append(state_root)
    sensitive.extend(Path(item).expanduser().resolve() for item in protected_paths)
    for protected in sensitive:
        if path.is_relative_to(protected) or protected.is_relative_to(path):
            raise ValueError(
                f"Refusing to expose a credential or runtime-state directory: {path}"
            )
    if "\n" in str(path) or "\x00" in str(path):
        raise ValueError("Unsupported project path")
    return path


def project_mount(path, config):
    protected = config.get("protectedPaths", []) + [
        binding["sourceFile"] for binding in config["secretBindings"].values()
    ]
    path = validate_host_path(path, config["hostHome"], config["stateDir"], protected)
    env = {
        "PATH": config["runtimePath"],
        "HOME": "/nonexistent",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_TERMINAL_PROMPT": "0",
    }

    def git(*args):
        result = subprocess.run(
            [config["git"], "-C", str(path), "rev-parse", *args],
            env=env,
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode:
            raise ValueError(f"Not an accessible Git working tree: {path}")
        return Path(result.stdout.strip()).resolve()

    root = validate_host_path(
        git("--show-toplevel"), config["hostHome"], config["stateDir"], protected
    )
    common = git("--path-format=absolute", "--git-common-dir")
    git_dir = git("--absolute-git-dir")
    if not common.is_relative_to(root) or not git_dir.is_relative_to(root):
        raise ValueError(
            "Git metadata is outside this checkout; use a standalone clone for now"
        )
    return root


def private_directory(path):
    path = Path(path)
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = path.lstat()
    if (
        not stat.S_ISDIR(info.st_mode)
        or info.st_uid != os.getuid()
        or info.st_mode & 0o077
    ):
        raise ValueError(f"Sandbox state must be a private, owned directory: {path}")
    return path


def check_kvm():
    if not os.access("/dev/kvm", os.R_OK | os.W_OK):
        raise ValueError(
            "Local microVMs require readable/writable /dev/kvm; no host fallback is permitted"
        )


def runtime_environment(config, run_dir):
    state = Path(config["stateDir"])
    return {
        "PATH": config["runtimePath"],
        "HOME": str(state / "runtime-home"),
        "XDG_CONFIG_HOME": str(state / "runtime-home" / ".config"),
        "XDG_DATA_HOME": str(state / "runtime-home" / ".local" / "share"),
        "XDG_RUNTIME_DIR": str(run_dir),
        "TMPDIR": str(run_dir),
        "MSB_HOME": str(state / "runtime"),
        "MSB_BACKEND": "local",
        "SSL_CERT_FILE": config["caBundle"],
        "TERM": os.environ.get("TERM", "xterm-256color"),
        "LANG": "C.UTF-8",
    }


def secret_configuration(bindings):
    definitions = {}
    values = {}
    for name, binding in bindings.items():
        if not re.fullmatch(r"[A-Z_][A-Z0-9_]*", name):
            raise ValueError(
                "Secret environment names must be uppercase shell identifiers"
            )
        if name in {
            "HOME",
            "PATH",
            "TMPDIR",
            "TERM",
            "LANG",
            "HTTP_PROXY",
            "HTTPS_PROXY",
            "ALL_PROXY",
            "NO_PROXY",
            "BASH_ENV",
            "ENV",
            "SHELLOPTS",
            "BASHOPTS",
            "PS4",
            "IFS",
            "CDPATH",
        } or name.startswith(("MSB_", "LD_", "PYTHON", "XDG_", "GIT_", "SSL_", "NIX_")):
            raise ValueError("Secret bindings cannot override host runtime controls")
        source = Path(binding["sourceFile"])
        if not source.is_absolute() or source.is_relative_to("/nix/store"):
            raise ValueError(
                "Secret sources must be absolute runtime paths outside the Nix store"
            )
        hosts = binding["allowedHosts"]
        if not hosts or any(
            not re.fullmatch(r"[a-zA-Z0-9.-]+", host) for host in hosts
        ):
            raise ValueError(
                "Every secret requires explicit destination hostnames, without wildcards"
            )
        with source.open() as stream:
            value = stream.read(65537).strip()
        if not value or len(value) > 65536 or any(char in value for char in "\r\n\x00"):
            raise ValueError(f"Secret {name} must contain a single nonempty token")
        values[name] = value
        definitions[name] = {
            "value": "${" + name + "}",
            "allow": hosts,
            "substitution": {
                "headers": True,
                "header_fields": ["authorization"],
                "query": False,
                "body": False,
            },
        }
    return definitions, values


def launch(config, options, pi_args):
    project = project_mount(options.project, config)
    key = hashlib.sha256(os.fsencode(project)).hexdigest()[:20]
    mounts = [{"bind": str(project), "target": "/workspace", "readonly": False}]
    seen = {project}
    for readonly, paths in [(True, options.repo_ro), (False, options.repo_rw)]:
        for path in paths:
            root = project_mount(path, config)
            if root in seen:
                raise ValueError("A repository may only be shared once")
            seen.add(root)
            suffix = hashlib.sha256(os.fsencode(root)).hexdigest()[:10]
            basename = re.sub(r"[^a-zA-Z0-9_.-]", "-", root.name)
            mounts.append(
                {
                    "bind": str(root),
                    "target": f"/repos/{basename}-{suffix}",
                    "readonly": readonly,
                }
            )
    volume = f"pi-sandbox-home-{key}"
    report = {
        "project": str(project),
        "mounts": mounts,
        "image": config["imageTag"],
        "guestHomeVolume": volume,
        "networkPolicy": config["networkPolicy"],
        "allowedHosts": config["allowedHosts"],
        "cpus": config["cpus"],
        "memory": config["memory"],
        "secretNames": list(config["secretBindings"]),
    }
    if options.diagnose:
        print(json.dumps(report, indent=2))
        return 0
    check_kvm()
    state = private_directory(config["stateDir"])
    locks = private_directory(state / "locks")
    private_directory(state / "runtime-home")
    private_directory(state / "runtime")
    runs = private_directory(state / "runs")
    descriptor = os.open(
        locks / key, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600
    )
    with os.fdopen(descriptor, "a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError(
                "This project's guest home is already in use by another pi-sandbox"
            ) from None
        with tempfile.TemporaryDirectory(prefix="session-", dir=runs) as temporary:
            env = runtime_environment(config, temporary)
            runtime = config["runtime"]
            cached = subprocess.run(
                [runtime, "image", "inspect", config["imageTag"]],
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            if cached.returncode:
                imported = subprocess.run(
                    [
                        runtime,
                        "load",
                        "--input",
                        config["image"],
                        "--tag",
                        config["imageTag"],
                    ],
                    env=env,
                )
                if imported.returncode:
                    return imported.returncode
            secrets, values = secret_configuration(config["secretBindings"])
            guest_home = config["guestHome"]
            runtime_config = {
                "cpus": config["cpus"],
                "memory": config["memory"],
                "pull_policy": "never",
                "workdir": "/workspace",
                "mounts": mounts
                + [{"named": volume, "target": guest_home, "create": "ensure-exists"}],
                "env": {"HOME": guest_home, "TERM": env["TERM"], "LANG": "C.UTF-8"},
                "network": {
                    "policy": config["networkPolicy"],
                    "allow": config["allowedHosts"],
                    "ports": config["ports"],
                    "tls": {
                        "enabled": bool(secrets or config["allowedHosts"]),
                        "verify_upstream": True,
                    },
                },
                "secrets": secrets,
            }
            filename = Path(temporary) / "sandbox.yaml"
            filename.write_text(json.dumps(runtime_config))
            filename.chmod(0o600)
            name = "pi-sandbox-" + uuid.uuid4().hex
            for mount in mounts:
                permission = "read-only" if mount["readonly"] else "READ/WRITE"
                print(
                    f"pi-sandbox: {mount['bind']} -> {mount['target']} ({permission})",
                    file=sys.stderr,
                )
            print(
                "pi-sandbox: all Pi processes run in the VM; shared project files remain exposed",
                file=sys.stderr,
            )
            command = [
                runtime,
                "run",
                "--conf",
                str(filename),
                "--name",
                name,
                config["imageTag"],
                "--",
                config["guestCommand"],
                *pi_args,
            ]
            try:
                result = subprocess.run(command, env={**env, **values})
                return (
                    result.returncode
                    if result.returncode >= 0
                    else 128 - result.returncode
                )
            except Terminated as interrupted:
                return 128 + interrupted.number
            except KeyboardInterrupt:
                return 130
            finally:

                def cleanup(arguments, timeout):
                    try:
                        return (
                            subprocess.run(
                                [runtime, *arguments],
                                env=env,
                                stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL,
                                timeout=timeout,
                                check=False,
                            ).returncode
                            == 0
                        )
                    except (OSError, subprocess.TimeoutExpired):
                        return False

                if not cleanup(["stop", "--timeout", "10", name], 15):
                    cleanup(["stop", "--force", name], 10)
                if not cleanup(["rm", name], 10):
                    print(
                        f"pi-sandbox: could not remove {name}; persistent guest state was retained",
                        file=sys.stderr,
                    )


def main():
    options, arguments = parse_options(sys.argv[1:])
    if not options.config:
        raise ValueError("Start this tool through the Nix-managed pi-sandbox launcher")
    with open(options.config) as stream:
        config = json.load(stream)

    def terminate(number, _frame):
        raise Terminated(number)

    previous = signal.signal(signal.SIGTERM, terminate)
    try:
        return launch(config, options, arguments)
    except Terminated as interrupted:
        return 128 + interrupted.number
    finally:
        signal.signal(signal.SIGTERM, previous)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        print(f"pi-sandbox: {error}", file=sys.stderr)
        sys.exit(1)
