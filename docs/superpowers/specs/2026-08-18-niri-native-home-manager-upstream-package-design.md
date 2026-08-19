# Native Home Manager Niri and Upstream Package Design

## Goal

Remove the `epireyn/niri-flake` dependency and split Niri ownership across the
upstreams that naturally own each concern:

- Home Manager renders and validates the user configuration.
- Nixpkgs provides NixOS session integration.
- `niri-wm/niri` provides the upstream-main compositor package.
- This repository retains only personal desktop policy, companion services,
  and host-specific hardware behavior.

The migration must preserve the currently rendered Niri behavior. Tracking
upstream `main` remains the default, the package is built locally, and failures
must stop loudly rather than silently selecting the Nixpkgs release package.

## Current State

The `niri` input points to `github:epireyn/niri-flake`. The repository imports
its Home Manager and NixOS modules, uses its `config.lib.niri.actions` helpers,
and selects its `niri-unstable` package output. The fork cache is disabled and
the package is rebuilt locally, but evaluating the configuration and package
still requires trusting a third-party module and package implementation.

At the time of this design, the locked epireyn package and official Niri main
both build Niri source commit
`e9b215fef4b11ad36776553fb8bd45118ef03b03`. The migration can therefore
change the renderer and package-provider trust boundary without changing the
compositor source revision.

The remaining reason for the fork has now disappeared. Home Manager merged a
native `wayland.windowManager.niri` module in PR #9685. The locked Home Manager
revision already contains structured KDL generation, raw KDL escape hatches,
package selection, config validation, systemd-unit installation, portal
integration, and Xwayland Satellite integration.

Niri's official repository now publishes `packages.${system}.niri` from its
own checkout. Its `flake.nix` is explicitly described as community-maintained,
but it lives in and is reviewed through the upstream Niri repository. It builds
the pinned source revision using that checkout's `Cargo.lock`. This is a
narrower and better-governed trust boundary than the external Niri flake.

Primary references:

- https://github.com/nix-community/home-manager/pull/9685
- https://github.com/nix-community/home-manager/blob/master/modules/services/window-managers/niri.nix
- https://github.com/niri-wm/niri/blob/main/flake.nix
- https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/programs/wayland/niri.nix
- https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/ni/niri/package.nix

## Ownership Boundary

### Package

Keep the input name `niri`, but point it directly at upstream main:

```nix
niri = {
  url = "github:niri-wm/niri";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Following the primary Nixpkgs input keeps Niri on the repository's normal
toolchain and dependency set. The official flake at the migration revision
declares no `rust-overlay` input, so the root configuration neither invents an
override for one nor adds an unused lock node.

Every enabled Linux consumer selects exactly:

```nix
inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri
```

There is no `or pkgs.niri` expression and no conditional automatic fallback.
Disabled Darwin evaluation must not reference the Linux-only upstream package.

### Home Manager

Home Manager's native `wayland.windowManager.niri` module owns:

- enabling the user-side Niri integration;
- the selected upstream package;
- generation of `$XDG_CONFIG_HOME/niri/config.kdl`;
- validation of that file with the exact selected package.

Every enabled Linux profile configures the native module explicitly:

```nix
wayland.windowManager.niri = {
  enable = true;
  package = niriPackage;
  checkConfig = true;
  systemd.enable = false;
  portalPackage = null;
  xwaylandSatellitePackage = null;
};
```

The three disabled convenience integrations are intentional. Home Manager
does not copy the compositor unit into `$XDG_DATA_HOME` or consider the active
compositor for restart during `sd-switch`. NixOS owns its Niri unit through the
Nixpkgs module. The official upstream flake installs units under
`$out/lib/systemd/user`, while Home Manager's package-unit importer consumes
`$out/share/systemd/user`; for CachyOS, system-manager therefore links the two
official unit files into `/etc/systemd/user`. Portal selection and the GNOME
portal service remain in `local.niri` and the shared user configuration.
Xwayland Satellite remains referenced by the existing absolute package path in
the generated KDL. These settings prevent the native module defaults from
creating overlapping owners or changing activation behavior.

The existing `local.niri` module remains the reusable policy layer. It keeps
the current Waybar, Mako, Fuzzel, lock screen, wallpaper, theme, scripts,
desktop portal service, output helper, and hardware options. It writes its Niri
settings into `wayland.windowManager.niri.settings` instead of
`programs.niri.settings`.

The migration does not use the native module as an excuse to redesign portals
or companion services. Those can be simplified later as separate behavioral
changes.

### NixOS and System Manager

NixOS uses the module already shipped by Nixpkgs:

```nix
programs.niri = {
  enable = true;
  package = niriPackage;
  useNautilus = false;
};
```

The external `inputs.niri.nixosModules.niri` import and
`niri-flake.cache.enable` option disappear. Setting `useNautilus = false`
preserves the repository's existing GTK file-chooser policy and avoids adding
Nautilus merely because the Nixpkgs module defaults to it. The Nixpkgs module
owns session registration, the Niri systemd unit and its
`restartIfChanged = false` safety policy, the GNOME portal dependency, graphics
integration, and keyring integration. Existing local greetd, PAM, portal,
session-variable, and GTK portal policy remains explicit and unchanged.

The CachyOS system-manager module continues to own native PAM, greetd, and
hyprlock integration. It also links `niri.service` and
`niri-shutdown.target` directly from the exact official package into
`/etc/systemd/user`, replacing the undeclared dependency on CachyOS's native
Niri unit without copying or rewriting upstream unit contents. Home Manager
installs the same Niri package and user configuration there but does not make
the compositor an `sd-switch`-managed Home Manager unit. System-manager does
not restart user units, so a changed absolute `ExecStart` takes effect at the
next login rather than terminating the active session.
`greetd.restartIfChanged = false` remains unchanged.

## Behavior-Preserving Configuration Translation

The two renderers use different Nix representations for the same KDL. The
migration therefore uses the rendered KDL as the behavioral source of truth,
not a superficial translation of the old option tree.

Before editing the renderer, build and save the Razer and Framework generated
`config.kdl` files as migration-only artifacts outside Git. Then translate:

- `config.lib.niri.actions` helpers to direct KDL-shaped attributes;
- no-argument nodes to empty attribute sets;
- action arguments to lists;
- bind properties such as `allow-when-locked` and `cooldown-ms` to `_props`;
- ordered or repeated output and rule nodes to `_children`;
- parameterized nodes such as named outputs to `_args`;
- the fork's abstract `enable`, animation `kind`, gradient, and rule shapes to
  the concrete nodes emitted in the current KDL.

The translation initially represents every currently emitted behavioral node,
including values supplied as defaults by the old renderer. It must not assume
that omitting a node is equivalent merely because the current Niri default
happens to match. Removing explicit defaults can be evaluated later as an
intentional behavior change.

The old and new files may differ in their generated header, whitespace,
floating-point formatting, or ordering of nodes whose order has no semantic
effect. They must preserve:

- every setting, node argument, and node property;
- output identities, scales, transforms, and disabled state;
- binding identities, commands, arguments, and lock/inhibit properties;
- order of repeated or potentially order-sensitive rules;
- startup commands, scripts, absolute package paths, and host-specific debug
  device paths;
- layout, animation, input, cursor, shadow, and Xwayland behavior.

Both generated files must build successfully with Home Manager's
`checkConfig`, which runs `niri validate` using the selected Niri package.

## Staged Migration

Implementation is split into two reviewable stages on one feature branch.
Neither stage is activated by the agent.

### Stage 1: Renderer Migration at the Existing Niri Revision

Remove the epireyn Home Manager and NixOS module imports, enable the native
modules, and translate the configuration while temporarily retaining the
currently locked epireyn `niri-unstable` package. This holds the compositor
source revision at `e9b215fef4b11ad36776553fb8bd45118ef03b03` while renderer
output is compared and validated. The native Home Manager portal, Xwayland,
and systemd convenience integrations are set explicitly as described above;
their defaults are not allowed to alter service ownership.

The stage is complete only when the generated Razer and Framework KDL files are
semantically equivalent to their baselines and every target evaluates.

### Stage 2: Official Upstream Package

Change the `niri` input URL to `github:niri-wm/niri`, follow primary Nixpkgs,
keep `rust-overlay` absent, and replace `niri-unstable` references with the
official `niri` package output. Perform a targeted lock update and review all
lock-file churn. No unrelated input revision may change. At the migration
boundary, the official input must still resolve to
`e9b215fef4b11ad36776553fb8bd45118ef03b03`; this stage changes the package
provider, not the Niri source under test.

Build the exact package with substitution disabled, then validate the already
proven configuration with that package. At this stage, system-manager also
links the package's `lib/systemd/user/niri.service` and
`niri-shutdown.target` into `/etc/systemd/user`; no Home Manager user-service
definition is added. This isolates package-source or Niri runtime failures from
renderer-translation failures.

## Update and Failure Contract

After migration, `just update-input niri` advances the official upstream input
to the newest commit reachable from `main`. It does not update Nixpkgs. Every
Niri update requires review of the targeted lock diff, upstream `flake.nix`,
and `Cargo.lock`, followed by the same package, configuration, and contract
checks. Verification compares the locked Niri revision, evaluated package
version, and `niri --version`; it does not rely on `package.src.rev`, because
the official package uses a fileset source.

If evaluation, compilation, or config validation fails:

- do not select `pkgs.niri` automatically;
- do not enable a binary cache;
- do not activate the failed generation;
- leave the failed lock change uncommitted or restore the previous known-good
  lock revision;
- record a long-lived deliberate upstream pin in `TODO.md`, including the
  failure, upstream reference, affected targets, and removal check.

The Nixpkgs release package is a deliberate manual recovery option, not a
runtime or evaluation fallback.

## Branch and Commit Structure

Work occurs in an isolated worktree on
`feat/niri-native-home-manager`, based on clean `main` commit `b2975e2`.

Implementation commits remain reviewable and behavior-oriented:

1. migrate configuration rendering to native Home Manager while retaining the
   existing package revision;
2. replace the epireyn input/package with the official upstream package;
3. finalize contracts, TODO history, and verification evidence where those
   changes do not naturally belong with the preceding commits.

Tests and contract changes are committed with the behavior they protect rather
than added as an unconnected cleanup commit. Planning documents live on the
feature branch and no unrelated files are staged.

## Targets and Validation

Target configurations:

- `homeConfigurations.razer14`
- `homeConfigurations.cachyos-framework13`
- `nixosConfigurations.razer14`
- `nixosConfigurations.dell-plex`
- `darwinConfigurations.PNH46YXX3Y`
- `systemConfigs.cachyos-framework13`
- `checks.x86_64-linux.configuration-contract`

Validation host: `framework13`, CachyOS Linux x86_64.

Minimum exact evaluations:

```text
nix eval .#homeConfigurations.razer14.activationPackage.drvPath
nix eval .#homeConfigurations.cachyos-framework13.activationPackage.drvPath
nix eval .#nixosConfigurations.razer14.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.dell-plex.config.system.build.toplevel.drvPath
nix eval .#darwinConfigurations.PNH46YXX3Y.config.system.build.toplevel.drvPath
nix eval .#systemConfigs.cachyos-framework13.drvPath
nix eval .#checks.x86_64-linux.configuration-contract.drvPath
```

Final verification also requires:

1. build both generated Niri configuration sources so `niri validate` runs;
2. review the baseline/new KDL diff for both enabled Home Manager profiles;
3. build `checks.x86_64-linux.configuration-contract`;
4. prove every enabled Linux system, standalone Home Manager profile, and
   embedded Home Manager profile resolves to the same official upstream
   derivation;
5. prove Home Manager leaves its native portal, Xwayland-package, and systemd
   integrations disabled while NixOS sets `useNautilus = false` and retains
   the Niri no-restart systemd policy;
6. prove system-manager sources both CachyOS user units from the same official
   package without defining an `sd-switch`-managed Niri service;
7. prove disabled Darwin evaluation does not reference the Linux package;
8. prove epireyn, its modules, overlays, package names, cache URLs, and cache
   keys are absent from active configuration;
9. compare the upstream Niri user unit with the pre-migration unit behavior and
   confirm Home Manager does not schedule the compositor for restart;
10. force a no-link, no-substitution rebuild of the exact Niri package;
11. run `just check`, formatting, and `git diff --check`;
12. inspect the final branch diff and staged paths before each commit.

CUDA-heavy system builds and all activation commands are outside scope. The
user will perform runtime activation after reviewing the completed branch.

## TODO Handling

The current active TODO entries for the epireyn module and package-source
exceptions become one resolved-history entry. Existing resolved Niri entries
remain as historical context, and the active CachyOS greetd lifecycle entry is
not part of this migration. The new resolution records:

- the original stalled-fork and `libdisplay-info` problem;
- the temporary epireyn trust boundary;
- the arrival of Home Manager's native module;
- the move to Niri upstream's official package output;
- preservation of source commit
  `e9b215fef4b11ad36776553fb8bd45118ef03b03` across the package-provider
  boundary;
- the retained targeted update, local-build, and fail-loud policies.

The Home Manager provenance link uses merged PR #9685. The older PR #8700 was
closed without merge and must not remain as the justification for the native
module.

No new exception is required for following upstream Niri main because that is
the selected permanent package policy. A new TODO is added only if the
implementation discovers a temporary pin or workaround outside this design.

## Rollback

The agent performs no switch, so implementation cannot alter the running Niri
session. Before user activation, rollback is deleting the worktree or reverting
the feature commits. After activation, the previous Home Manager or NixOS
generation remains available while the source branch can be reverted.

## Success Criteria

The migration is complete when:

- the repository contains no active dependency on `epireyn/niri-flake`;
- native Home Manager generates and validates both Niri configurations;
- native Nixpkgs provides NixOS integration;
- all enabled Linux consumers use the same locally built official upstream-main
  package;
- updates fail loudly without a hidden downgrade;
- the old and new rendered configurations are behaviorally equivalent;
- every exact target and repository check passes without activation.
