# Session-Safe greetd Activation Design

## Problem

`systemConfigs.cachyos-framework13` manages `greetd.service` through
system-manager. A recent Nixpkgs update changed only the Nix-store paths in the
unit's generated `PATH`, but system-manager treats a changed unit store path as
a service change and reloads or restarts it by default. Because greetd owns the
interactive Niri session, that restart logs the user out.

System-manager records its new service state only after service activation.
Ending the login session can interrupt the invoking switch before that write,
leaving the old greetd unit path in its state file. Later switches then detect
the same apparent change and repeat the logout.

## Selected Design

Set `systemd.services.greetd.restartIfChanged = false` in the reusable
system-manager Niri module. The generated unit will contain
`X-RestartIfChanged=false`, which the pinned system-manager activator explicitly
honors when comparing changed unit paths.

System-manager will continue to install the new unit and finish activation, but
it will leave the running greetd process—and therefore the current Niri
session—alone. The completed activation will also record the current unit path,
breaking the stale-state loop.

## Operational Tradeoff

Changes to the greetd unit or its generated environment will not take effect in
the running daemon during a switch. They take effect at the next reboot or an
intentional greetd restart performed when ending the graphical session is
acceptable. This is preferable to an unannounced logout during routine system
activation.

The policy applies only to the Framework/CachyOS system-manager greetd unit. It
does not alter NixOS greetd behavior, Home Manager activation, or Niri's own
restart behavior.

## Regression Contract

Extend `checks.x86_64-linux.configuration-contract` to require the rendered
Framework greetd unit to contain `X-RestartIfChanged=false`. Write this assertion
first and confirm it fails against the current module, then add the single
service option and confirm it passes.

Validation consists of the exact Framework system-manager and configuration
contract evaluations, the contract build, direct inspection of the rendered
unit, formatting, and whitespace checks. No activation command is part of this
change.

## Exception Tracking

Record the policy in `TODO.md` with the observed restart/state-loop cause and an
obsolescence check against system-manager. Remove it only if upstream gains a
session-safe activation mechanism that can update display-manager units without
restarting the active graphical session.
