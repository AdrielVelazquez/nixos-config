# Session-Safe greetd Activation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent Framework system-manager switches from restarting greetd and terminating the active Niri login session.

**Architecture:** Keep the existing custom CachyOS greetd unit, but set its supported `restartIfChanged` policy to false. Protect the behavior with the existing cross-output configuration contract by checking the rendered unit directive, and document when the policy can be removed.

**Tech Stack:** Nix flakes, system-manager, systemd unit generation, flake-parts configuration contract

## Global Constraints

- Target only `systemConfigs.cachyos-framework13`; do not change NixOS or Home Manager greetd behavior.
- Preserve the user-owned `flake.lock` modification and all unrelated changes.
- Use `systemd.services.greetd.restartIfChanged = false`; do not patch System Manager or manipulate its state file.
- Verify the rendered unit contains `X-RestartIfChanged=false`.
- Do not run `system-manager switch`, `nix run`, Home Manager activation, or any other live-system mutation.
- Stage explicit paths only.

---

### Task 1: Enforce and implement the session-safe greetd policy

**Files:**
- Modify: `parts/checks.nix`
- Modify: `modules/system-manager/niri.nix`

**Interfaces:**
- Consumes: `frameworkSystem.systemd.units."greetd.service".text` and the Nixpkgs systemd service option `restartIfChanged`.
- Produces: a rendered greetd unit containing `X-RestartIfChanged=false`, which the pinned System Manager activator interprets as “install but do not restart this changed service.”

- [ ] **Step 1: Write the failing rendered-unit contract**

Add the rendered unit binding beside the existing greetd configuration binding in `parts/checks.nix`:

```nix
  greetdConfig = frameworkSystem.environment.etc."greetd/config.toml".text;
  greetdUnit = frameworkSystem.systemd.units."greetd.service".text;
```

Add this assertion beside the existing greetd contract:

```nix
          {
            assertion = lib.hasInfix "X-RestartIfChanged=false" greetdUnit;
            message = "Framework greetd must not restart during system-manager activation";
          }
```

- [ ] **Step 2: Run the contract and verify the expected red result**

Run:

```bash
rtk nix eval .#checks.x86_64-linux.configuration-contract.drvPath
```

Expected: evaluation fails with only
`Framework greetd must not restart during system-manager activation`, proving
the contract detects the current unsafe default.

- [ ] **Step 3: Add the minimal service policy**

Add one option to the existing service declaration in
`modules/system-manager/niri.nix`:

```nix
    systemd.services.greetd = {
      restartIfChanged = false;

      description = "greetd greeter daemon";
```

- [ ] **Step 4: Evaluate the exact target immediately**

Run:

```bash
rtk nix eval .#systemConfigs.cachyos-framework13.drvPath
```

Expected: returns the Framework system-manager derivation path without an
option or unit-rendering error.

- [ ] **Step 5: Verify the contract turns green**

Run:

```bash
rtk nix eval .#checks.x86_64-linux.configuration-contract.drvPath
```

Expected: returns the configuration-contract derivation path.

- [ ] **Step 6: Inspect the real rendered unit**

Run:

```bash
rtk nix eval --raw .#systemConfigs.cachyos-framework13 \
  --apply 'c: c.config.systemd.units."greetd.service".text'
```

Expected: the `[Service]` section contains exactly
`X-RestartIfChanged=false`; the existing `/usr/bin/greetd` command and tty
settings remain unchanged.

- [ ] **Step 7: Build the regression contract**

Run:

```bash
rtk nix build .#checks.x86_64-linux.configuration-contract --no-link
```

Expected: exits successfully without activation.

---

### Task 2: Record and deliver the lifecycle policy

**Files:**
- Modify: `TODO.md`
- Commit: `parts/checks.nix`
- Commit: `modules/system-manager/niri.nix`
- Commit: `TODO.md`
- Commit: `docs/superpowers/plans/2026-08-18-greetd-session-safe-activation.md`

**Interfaces:**
- Consumes: the verified rendered-unit contract from Task 1 and the upstream behavior documented by Nixpkgs and System Manager.
- Produces: an actionable exception record and one reviewable implementation commit, without including the user's `flake.lock` update.

- [ ] **Step 1: Add the exact TODO entry**

Add this active exception to `TODO.md`:

```markdown
- `systemd.services.greetd.restartIfChanged = false` in `modules/system-manager/niri.nix`: target `systemConfigs.cachyos-framework13`. Original issue: System Manager restarts changed service units by default, but greetd owns the active Niri login session, so dependency or generated-unit churn during a switch logs the user out and can interrupt activation before its new state is recorded. This matches Nixpkgs's greetd module, which disables restart-on-change specifically to avoid killing user sessions, and is supported by numtide/system-manager PR #438. Changed greetd definitions are installed but take effect only after an intentional restart from SSH/another TTY or a reboot. Obsolescence check: retain this while the repository owns a custom CachyOS greetd unit; remove it only if that unit is replaced by an upstream module carrying equivalent lifecycle protection or System Manager gains display-manager-aware restart deferral. After such a change, switch while Niri is active and verify greetd's `MainPID` and the desktop session survive while activation state advances.
```

- [ ] **Step 2: Run final static verification**

Run:

```bash
rtk nix fmt -- --ci .
rtk git diff --check
rtk git status --short --untracked-files=all
```

Expected: formatting and whitespace checks pass. The intended implementation
files and the pre-existing, unstaged `flake.lock` modification are the only
working-tree changes.

- [ ] **Step 3: Stage only the approved implementation files**

Run:

```bash
rtk git add parts/checks.nix modules/system-manager/niri.nix TODO.md
rtk git add -f docs/superpowers/plans/2026-08-18-greetd-session-safe-activation.md
rtk git diff --cached --check
rtk git diff --cached --stat
rtk git status --short --untracked-files=all
```

Expected: exactly the four approved paths are staged; `flake.lock` remains
modified and unstaged.

- [ ] **Step 4: Commit and inspect the fix**

Run:

```bash
rtk git commit -m "fix: preserve Niri session during system switch"
rtk git show --stat --oneline --summary HEAD
rtk git status --short --untracked-files=all
```

Expected: the implementation commit contains exactly four files, while the
user-owned `flake.lock` modification remains uncommitted and no activation has
run.
