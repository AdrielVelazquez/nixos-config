# Experimental whole-process Pi sandbox

`pi-sandbox` runs the managed Pi configuration inside a local Microsandbox microVM.
The normal `pi` command, aliases, host sessions and credentials are not replaced.

## Enable or disable

The shared Home Manager import includes `modules/home-manager/pi-sandbox.nix`.
Its option defaults off. The Framework trial enables only the separate launcher:

```nix
local.pi.sandbox.enable = true;
```

Set it to `false` to remove the launcher from the next Home Manager generation.
No VM starts during activation or login. Disabling does not delete guest state
or intentionally terminate an already running sandbox session.

The initial package supports x86_64 Linux with readable/writable `/dev/kvm`.
Razer is not enabled. This change does not modify system virtualization permissions.

## Run

From a normal Git checkout:

```sh
pi-sandbox --diagnose
pi-sandbox
pi-sandbox -- --session SESSION_ID
pi-sandbox -- -p "run the tests"
```

Launcher options come before `--`; Pi arguments come after it.

The checkout root is mounted read/write at `/workspace`. Pi, its extensions,
Headroom, language servers, debugger adapters, Python kernel, jobs and native
children all execute inside the guest. The guest image contains Nix-generated
configuration and tool closures, not a bind mount of the host's Nix store.

A fresh VM is removed when Pi exits. Its project-specific private home volume
persists, including guest sessions, authentication and caches. Nix-generated Pi
defaults refresh on each invocation; guest credentials and sessions are not
overwritten. Only one launcher may use a project's guest home at a time.

Missing KVM, invalid mounts, image-import failures and startup errors abort.
There is no fallback to running Pi on the host.

## Additional repositories

```sh
pi-sandbox --repo-ro /path/to/reference-repo
pi-sandbox --repo-rw /path/to/second-working-repo -- -p "update both projects"
```

Additional repos appear at printed paths under `/repos/<name>-<hash>`.
Mounts are explicit; home, credential directories and sandbox runtime state
cannot be shared through these options. Symlinks are resolved before validation.

This first version rejects linked worktrees whose Git metadata is outside the
shared checkout. Use a standalone clone rather than exposing an entire parent
tree. It also starts at the checkout root, not the host's current subdirectory.

**Writable mounts are writable host files.** Guest code can modify or delete
those projects, including their Git metadata. Project-local `.env`, tokens in
Git configuration and other files already in the checkout are exposed with it.
Use a disposable checkout or a read-only reference repo for untrusted content.

## Credentials

The launcher constructs a clean runtime environment. It does not forward host
API keys, SSH agents, proxy credentials, cloud profiles or Tuios control variables.
It never imports the host's `auth.json`, `mcp-auth.json` or SSH keys.

Guest authentication is separate and is available to code inside that guest.
Native MCP connections that require host credentials will not automatically
work. In particular, declaring GitHub MCP is not the same as authenticating it.

Compatible API tokens can be explicitly bound through Microsandbox's
Authorization-header substitution:

```nix
local.pi.sandbox.secretBindings.CODEX_GITHUB_PERSONAL_ACCESS_TOKEN = {
  sourceFile = config.sops.secrets.codex_github_token.path;
  allowedHosts = [ "api.githubcopilot.com" ];
};
```

Only a runtime path is stored by Nix. The launcher reads the token at runtime,
and the sandbox configuration retains an environment reference. The guest gets
a placeholder; the runtime substitutes the real token at an approved destination.
Never put a token literal or a decrypted secret file in a Nix expression.

This is not SSH forwarding and cannot replace a key needed for guest-side signing.
An approved endpoint receives the real token and could return it to the guest.
Use narrow permissions and hosts. Real provider/MCP authentication and token
substitution require their own end-to-end verification; synthetic startup tests
are not proof that a real credential works.

Framework's work provider remains configured and its Headroom proxy runs inside
the guest. Actual work-network identity and successful live inference must be
checked separately; no host inference server or authentication directory is shared.

## Resources and networking

```nix
local.pi.sandbox = {
  enable = true;
  cpus = 2;
  memory = "4G";
  extraPackages = [ pkgs.cargo pkgs.rustc ];
  # networkPolicy = "none"; # Offline instead of public outbound access.
  # allowedHosts = [ "api.example.com" ]; # Nonempty means an outbound allowlist.
  # ports = [ "127.0.0.1:3000:3000" ]; # Explicit host-loopback mapping.
};
```

The default network policy permits public outbound access, not host/LAN/metadata
access. No ports are published by default. Network access and any credential
permission remain capabilities deliberately granted to guest code.

State defaults to Home Manager's `xdg.stateHome/pi-sandbox` (normally
`~/.local/state/pi-sandbox`), fixed by Nix rather than a per-command environment
override. The module's `stateDir` can select another absolute private directory.
The initial Framework image is approximately 7.4 GiB because it includes the
managed tools and Headroom dependencies; cold imports need additional disk/time.
The outer archive is an uncompressed Docker tar, as required by the tested
runtime import path. Compressed filesystem layers are a separate format concern.

Host Tuios hooks are deliberately omitted, and no host control socket is mounted.
Pi's UI remains configured, but host Inbox/resume integration is not claimed.
Host Git credential helpers and unrelated desktop packages are not reproduced.

## Verification

These commands build/evaluate only; they do not activate the configuration:

```sh
nix eval .#homeConfigurations.cachyos-framework13.activationPackage.drvPath
nix build --no-link .#checks.x86_64-linux.pi-sandbox
nix build --no-link .#checks.x86_64-linux.pi-sandbox-image
nix build --no-link .#homeConfigurations.cachyos-framework13.config.local.pi.sandbox.launcherPackage
```

Run the disposable KVM smoke with the resulting launcher path:

```sh
python3 -B tests/pi/sandbox-smoke.py --launcher /nix/store/…-pi-sandbox/bin/pi-sandbox
```

The smoke creates its own temporary Git repo, state/catalog and synthetic model.
It refuses real secret bindings, then creates its own synthetic token to check
guest placeholders and catalog persistence. Native MCP is disabled for that run;
live OAuth/MCP credentials, private cloning and real inference are not verified
by it. No system switch, host sign-in or live-session restart is performed.

## Sources

- [Microsandbox release](https://github.com/superradcompany/microsandbox/releases/tag/v0.7.11)
- [Image archive import](https://docs.microsandbox.dev/cli/image-commands)
- [Filesystem isolation](https://docs.microsandbox.dev/security/filesystem)
- [Network policy](https://docs.microsandbox.dev/security/network)
- [Credential substitution and its limits](https://docs.microsandbox.dev/sandboxes/secrets)
