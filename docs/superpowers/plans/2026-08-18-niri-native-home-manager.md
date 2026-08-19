# Native Home Manager Niri Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `epireyn/niri-flake` with Home Manager's native Niri configuration module, Nixpkgs's native NixOS session module, and the official upstream Niri package while preserving the rendered desktop behavior.

**Architecture:** `local.niri` remains the repository's reusable desktop-policy layer and writes KDL-shaped values into `wayland.windowManager.niri.settings`. Home Manager installs the exact upstream package and validates the generated KDL, Nixpkgs owns NixOS session integration, and system-manager retains the CachyOS-native PAM/greetd boundary while sourcing upstream user units from the same package. The renderer moves first while the Niri source stays at `e9b215fef4b11ad36776553fb8bd45118ef03b03`; the package provider changes only after both generated configurations match their baselines.

**Tech Stack:** Nix flakes, flake-parts, Home Manager, NixOS modules, system-manager, KDL, Niri

**Spec:** `docs/superpowers/specs/2026-08-18-niri-native-home-manager-upstream-package-design.md`

## Global Constraints

- Work only on branch `feat/niri-native-home-manager` in `/home/adriel/.nixos/.worktrees/niri-native-home-manager`.
- Preserve Niri source commit `e9b215fef4b11ad36776553fb8bd45118ef03b03` across the renderer and package-provider boundary.
- Every enabled Linux consumer must use the exact selected Niri input package; there is no `pkgs.niri` fallback.
- Home Manager must set `systemd.enable = false`, `portalPackage = null`, and `xwaylandSatellitePackage = null` for Niri.
- NixOS must set `programs.niri.useNautilus = false` and retain the native module's no-restart Niri service policy.
- CachyOS system-manager must source `niri.service` and `niri-shutdown.target` from the exact official package under `/etc/systemd/user` without managing their runtime state.
- Disabled Darwin evaluation must never reference the Linux-only upstream package.
- Update only the `niri` lock input; unrelated lock revisions must not change.
- Keep both Niri fork caches absent and force a local, no-substitution package build.
- Do not run `home-manager switch`, `system-manager switch`, `nixos-rebuild switch`, or any other activation command.
- Prefix every shell command with `rtk`; stage explicit paths only.

## File Map

- `modules/home-manager/niri/default.nix`: select the Linux package, configure the native Home Manager module, and hold the KDL-shaped desktop policy.
- `modules/home-manager/niri/services.nix`: resolve the Niri executable from the native Home Manager package option.
- `users/adriel/default.nix`: provide the Razer output nodes in native KDL form.
- `users/adriel-cachyos/default.nix`: provide the Framework output nodes in native KDL form.
- `parts/home-manager.nix`: stop importing the external Home Manager module.
- `parts/darwin.nix`: stop importing the external module while keeping Niri disabled on Darwin.
- `modules/system/niri.nix`: use Nixpkgs's built-in Niri module and exact selected package.
- `modules/system-manager/niri.nix`: retain native PAM/greetd behavior and install the exact official user units.
- `parts/checks.nix`: enforce native option ownership, package identity, session safety, and absence of fork cache behavior.
- `flake.nix`: point the `niri` input at `github:niri-wm/niri`.
- `flake.lock`: retain only the targeted `niri` input update and removal of its obsolete descendants.
- `TODO.md`: resolve the two active Niri exceptions while retaining the CachyOS greetd exception.
- `/tmp/niri-native-home-manager-baseline-e9b215f/{razer14,cachyos-framework13}.kdl`: untracked renderer baselines.

---

### Task 1: Native Renderer and NixOS Integration at the Existing Niri Revision

**Files:**
- Modify: `parts/checks.nix`
- Modify: `parts/home-manager.nix`
- Modify: `parts/darwin.nix`
- Modify: `modules/home-manager/niri/default.nix`
- Modify: `modules/home-manager/niri/services.nix`
- Modify: `modules/system/niri.nix`
- Modify: `users/adriel/default.nix`
- Modify: `users/adriel-cachyos/default.nix`
- Test: `checks.x86_64-linux.configuration-contract`
- Test fixture outside Git: `/tmp/niri-native-home-manager-baseline-e9b215f/razer14.kdl`
- Test fixture outside Git: `/tmp/niri-native-home-manager-baseline-e9b215f/cachyos-framework13.kdl`

**Interfaces:**
- Consumes: `inputs.niri.packages.x86_64-linux.niri-unstable` at source revision `e9b215fef4b11ad36776553fb8bd45118ef03b03`.
- Produces: `wayland.windowManager.niri` for both enabled standalone profiles and the enabled Razer embedded profile; `programs.niri` from Nixpkgs for the enabled Razer NixOS system.
- Produces: generated source at `config.xdg.configFile."niri/config.kdl".source`.

- [ ] **Step 1: Verify the immutable renderer baselines**

Run:

```bash
rtk proxy sha256sum \
  /tmp/niri-native-home-manager-baseline-e9b215f/razer14.kdl \
  /tmp/niri-native-home-manager-baseline-e9b215f/cachyos-framework13.kdl
rtk jq -e '.nodes["niri-unstable"].locked.rev == "e9b215fef4b11ad36776553fb8bd45118ef03b03"' flake.lock
```

Expected checksums:

```text
cd4187acd8560456ea84a0883a18d9e951090ab77889833a9e7994750a980e71  /tmp/niri-native-home-manager-baseline-e9b215f/razer14.kdl
c999f1bd693435f4ed80ad1a15f49b3b91a1fc7d022b20e41b229b8fb8d6149e  /tmp/niri-native-home-manager-baseline-e9b215f/cachyos-framework13.kdl
```

- [ ] **Step 2: Write the failing native-ownership contract**

In `parts/checks.nix`, replace direct `programs.niri` Home Manager assumptions with native-module values and add helpers that fail safely while the external module still disables the native module:

```nix
niriUnstable = inputs.niri.packages.${systems.linux}.niri-unstable;
nativeNiri = home: lib.attrByPath [ "wayland" "windowManager" "niri" ] { } home;
razerNativeNiri = nativeNiri razerHome;
frameworkNativeNiri = nativeNiri frameworkHome;
razerEmbeddedNativeNiri = nativeNiri razerEmbeddedHome;
darwinNativeNiri = nativeNiri darwinEmbeddedHome;
```

Add these assertions to `configurationContract`:

```nix
{
  assertion =
    (razerNativeNiri.enable or false)
    && (frameworkNativeNiri.enable or false)
    && (razerEmbeddedNativeNiri.enable or false);
  message = "Enabled Linux Home Manager profiles must use the native Niri module";
}
{
  assertion =
    !(razerNativeNiri.systemd.enable or true)
    && !(frameworkNativeNiri.systemd.enable or true)
    && (razerNativeNiri.portalPackage or null) == null
    && (frameworkNativeNiri.portalPackage or null) == null
    && (razerNativeNiri.xwaylandSatellitePackage or null) == null
    && (frameworkNativeNiri.xwaylandSatellitePackage or null) == null;
  message = "Home Manager Niri must not overlap systemd, portal, or Xwayland ownership";
}
{
  assertion =
    !(lib.attrByPath [ "programs" "niri" "useNautilus" ] true razerSystem)
    && !(lib.attrByPath [ "systemd" "user" "services" "niri" "restartIfChanged" ] true razerSystem);
  message = "NixOS Niri must retain GTK portal and session-safe restart policy";
}
```

Replace the old package assertion with an assertion over enabled consumers only:

```nix
{
  assertion =
    (razerNativeNiri.package or null) != null
    && (frameworkNativeNiri.package or null) != null
    && (razerEmbeddedNativeNiri.package or null) != null
    && toString razerNativeNiri.package == toString niriUnstable
    && toString frameworkNativeNiri.package == toString niriUnstable
    && toString razerSystem.programs.niri.package == toString niriUnstable
    && toString razerEmbeddedNativeNiri.package == toString niriUnstable
    && !(dellSystem.programs.niri.enable)
    && !(darwinNativeNiri.enable or false);
  message = "Enabled Linux Niri consumers must share the selected package while Dell and Darwin stay disabled";
}
```

- [ ] **Step 3: Run the contract and verify the red state**

Run:

```bash
rtk nix eval .#checks.x86_64-linux.configuration-contract.drvPath
```

Expected: evaluation fails with the new native-module ownership messages because epireyn still disables `wayland.windowManager.niri`.

- [ ] **Step 4: Replace external module imports and NixOS integration**

Remove `inputs.niri.homeModules.niri` from `parts/home-manager.nix` and `parts/darwin.nix`; the pinned Home Manager already loads its native module. Replace `modules/system/niri.nix` with the Nixpkgs-owned configuration:

```nix
let
  cfg = config.local.niri;
  niriPackage = inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri-unstable;
in
{
  options.local.niri.enable = lib.mkEnableOption "niri scrollable-tiling Wayland compositor";

  config = lib.mkIf cfg.enable {
    programs.niri = {
      enable = true;
      package = niriPackage;
      useNautilus = false;
    };

    security.pam.services.hyprlock = { };

    services.greetd = {
      enable = true;
      settings.default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd niri-session";
        user = "greeter";
      };
    };

    environment.sessionVariables = {
      NIXOS_OZONE_WL = "1";
      ELECTRON_OZONE_PLATFORM_HINT = "wayland";
      XDG_CURRENT_DESKTOP = "niri";
      XDG_SESSION_TYPE = "wayland";
    };

    xdg.portal = {
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
      config.niri = {
        default = [
          "gnome"
          "gtk"
        ];
        "org.freedesktop.impl.portal.Access" = "gtk";
        "org.freedesktop.impl.portal.FileChooser" = "gtk";
        "org.freedesktop.impl.portal.Notification" = "gtk";
        "org.freedesktop.impl.portal.Secret" = "gnome-keyring";
      };
    };
  };
}
```

- [ ] **Step 5: Configure the native Home Manager ownership boundary**

In `modules/home-manager/niri/default.nix`, keep the Linux-only `niriPackage` lazy and place every package reference inside `lib.mkIf cfg.enable`. Replace the external import assignment with:

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

Change `modules/home-manager/niri/services.nix` to resolve:

```nix
niriBin = lib.getExe config.wayland.windowManager.niri.package;
```

This prevents Home Manager from linking `niri.service` into `$XDG_DATA_HOME/systemd/user` or considering the active compositor for `sd-switch` restart. NixOS supplies its unit through the native module; Task 2 makes system-manager source the official package units for CachyOS.

- [ ] **Step 6: Translate the old renderer shapes to native KDL shapes**

Rename the settings root to `wayland.windowManager.niri.settings` and encode all values emitted by the old renderer, including defaults. Use these exact structural forms:

```nix
wayland.windowManager.niri.settings = {
  input = {
    keyboard = {
      xkb = {
        layout = "us";
        model = "";
        rules = "";
        variant = "";
      };
      repeat-delay = 600;
      repeat-rate = 25;
      track-layout = "global";
    };
    touchpad = {
      tap = { };
      natural-scroll = { };
      click-method = "clickfinger";
    };
  };

  screenshot-path = "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png";
  prefer-no-csd = { };

  layout = {
    gaps = 16;
    struts = {
      left = 0;
      right = 0;
      top = 0;
      bottom = 0;
    };
    focus-ring = {
      width = 3;
      active-gradient._props = {
        angle = 45;
        from = style.palette.accent;
        relative-to = "workspace-view";
        to = style.palette.accentAlt;
      };
      inactive-color = style.palette.inactive;
    };
    border.off = { };
    background-color = style.palette.background;
    shadow = {
      on = { };
      offset._props = {
        x = 0;
        y = 5;
      };
      softness = 30;
      spread = 5;
      draw-behind-window = false;
      color = "#0007";
    };
    default-column-width.proportion = 1.0;
    preset-column-widths._children = [
      { proportion = 1.0 / 3.0; }
      { proportion = 1.0 / 2.0; }
      { proportion = 2.0 / 3.0; }
    ];
    center-focused-column = "never";
  };

  cursor = {
    xcursor-theme = "default";
    xcursor-size = 24;
    hide-after-inactive-ms = 3000;
  };
  hotkey-overlay.skip-at-startup = { };
  spawn-at-startup = [ "kitty" ];
  window-rule = {
    geometry-corner-radius = [ 12.0 12.0 12.0 12.0 ];
    clip-to-geometry = true;
  };
  animations = {
    slowdown = 1.0;
    window-close = {
      duration-ms = 200;
      curve = "ease-out-expo";
    };
    window-open = {
      duration-ms = 200;
      curve = "ease-out-expo";
    };
    workspace-switch.spring._props = {
      damping-ratio = 0.8;
      epsilon = 0.0001;
      stiffness = 1000;
    };
  };
  xwayland-satellite.path = lib.getExe pkgs.xwayland-satellite;
};
```

Keep the current conditional `debug` values, but attach them to this native settings tree. Translate every binding without `config.lib.niri.actions`:

```nix
binds = {
  "Mod+D".spawn = [ (lib.getExe pkgs.fuzzel) ];
  "Super+Alt+L".spawn-sh = [ scripts.lockScreen ];
  "Mod+Shift+Slash".show-hotkey-overlay = { };
  "Mod+1".focus-workspace = [ 1 ];
  "Mod+Minus".set-column-width = [ "-10%" ];
  "Print".screenshot = { };
  "Mod+WheelScrollDown" = {
    _props.cooldown-ms = 150;
    focus-workspace-down = { };
  };
  "XF86AudioRaiseVolume" = {
    _props.allow-when-locked = true;
    spawn-sh = [ scripts.volumeRaise ];
  };
  "Mod+Escape" = {
    _props.allow-inhibiting = false;
    toggle-keyboard-shortcuts-inhibit = { };
  };
};
```

Apply those six exact forms to every existing binding: `spawn`, `spawn-sh`, no-argument action, integer/string argument action, action with `_props.cooldown-ms`, and action with `_props.allow-when-locked` or `_props.allow-inhibiting`. Preserve every existing binding key, command, script, argument, and property; delete the `with config.lib.niri.actions` scope entirely.

- [ ] **Step 7: Translate both host output lists**

In both `users/adriel/default.nix` and `users/adriel-cachyos/default.nix`, replace `programs.niri.settings.outputs` with this ordered native list:

```nix
wayland.windowManager.niri.settings._children = [
  {
    output = {
      _args = [ "Apple Computer Inc StudioDisplay 0x92E55162" ];
      scale = 1.0;
      transform = "normal";
    };
  }
  {
    output = {
      _args = [ "DP-8" ];
      off = { };
      transform = "normal";
    };
  }
  {
    output = {
      _args = [ "LG Electronics LG HDR 4K 0x00017E3D" ];
      scale = 1.0;
      transform = "normal";
    };
  }
  {
    output = {
      _args = [ "LG Electronics LG HDR 4K 0x0002C15B" ];
      scale = 1.0;
      transform = "normal";
    };
  }
  {
    output = {
      _args = [ "Unknown Unknown Unknown" ];
      off = { };
      transform = "normal";
    };
  }
  {
    output = {
      _args = [ "eDP-1" ];
      scale = 1.1;
      transform = "normal";
    };
  }
];
```

Remove the standalone `programs.niri.enable = true` from the Framework user because `local.niri.enable` now drives the native module.

- [ ] **Step 8: Update the passing side of the configuration contract**

Change Xwayland and package checks to native paths:

```nix
razerNativeNiri.settings.xwayland-satellite.path
frameworkNativeNiri.settings.xwayland-satellite.path
razerNativeNiri.package.doCheck
frameworkNativeNiri.package.doCheck
```

Delete the assertion for `niri-flake.cache.enable`; the option must no longer exist. Retain `hasNoNiriCache` for all managed hosts.

- [ ] **Step 9: Format and run exact stage-one evaluation**

Run:

```bash
rtk nix fmt parts/checks.nix parts/home-manager.nix parts/darwin.nix \
  modules/home-manager/niri/default.nix modules/home-manager/niri/services.nix \
  modules/system/niri.nix users/adriel/default.nix users/adriel-cachyos/default.nix
rtk nix eval .#homeConfigurations.razer14.activationPackage.drvPath
rtk nix eval .#homeConfigurations.cachyos-framework13.activationPackage.drvPath
rtk nix eval .#nixosConfigurations.razer14.config.system.build.toplevel.drvPath
rtk nix eval .#nixosConfigurations.dell-plex.config.system.build.toplevel.drvPath
rtk nix eval .#darwinConfigurations.PNH46YXX3Y.config.system.build.toplevel.drvPath
rtk nix eval .#systemConfigs.cachyos-framework13.drvPath
rtk nix eval .#checks.x86_64-linux.configuration-contract.drvPath
```

Expected: all seven commands return derivation paths. `flake.lock` remains byte-identical.

- [ ] **Step 10: Build, validate, and compare both native KDL files**

Run:

```bash
niri_razer_new="$(rtk nix build --no-link --print-out-paths --impure --expr '(builtins.getFlake (toString ./.)).homeConfigurations.razer14.config.xdg.configFile."niri/config.kdl".source')"
niri_framework_new="$(rtk nix build --no-link --print-out-paths --impure --expr '(builtins.getFlake (toString ./.)).homeConfigurations.cachyos-framework13.config.xdg.configFile."niri/config.kdl".source')"
rtk diff /tmp/niri-native-home-manager-baseline-e9b215f/razer14.kdl "$niri_razer_new"
rtk diff /tmp/niri-native-home-manager-baseline-e9b215f/cachyos-framework13.kdl "$niri_framework_new"
```

Expected: both builds run the selected package's `niri validate`. Review the full diffs; only the generated header, whitespace, floating-point spelling, and semantically irrelevant top-level ordering may differ. Every baseline node, property, argument, rule order, output order, and store-path command must remain represented.

- [ ] **Step 11: Commit stage one**

Run:

```bash
rtk git status --short
rtk git add parts/checks.nix parts/home-manager.nix parts/darwin.nix \
  modules/home-manager/niri/default.nix modules/home-manager/niri/services.nix \
  modules/system/niri.nix users/adriel/default.nix users/adriel-cachyos/default.nix
rtk git diff --cached --check
rtk git diff --cached
rtk git commit -m "refactor: use native Niri modules"
```

---

### Task 2: Official Upstream Package and Targeted Lock Migration

**Files:**
- Modify: `parts/checks.nix`
- Modify: `flake.nix`
- Modify: `flake.lock`
- Modify: `modules/home-manager/niri/default.nix`
- Modify: `modules/system/niri.nix`
- Modify: `modules/system-manager/niri.nix`
- Test: `checks.x86_64-linux.configuration-contract`

**Interfaces:**
- Consumes: official `inputs.niri.packages.${system}.niri` and primary `inputs.nixpkgs`.
- Produces: one exact Niri derivation shared by all enabled Linux consumers.
- Produces: `just update-input niri` semantics that advance official Niri main without advancing Nixpkgs.

- [ ] **Step 1: Write the failing official-package contract**

In `parts/checks.nix`, define the expected official output without crashing when it is absent:

```nix
niriUpstream = lib.attrByPath [ "packages" systems.linux "niri" ] null inputs.niri;
frameworkNiriServiceSource =
  lib.attrByPath [ "environment" "etc" "systemd/user/niri.service" "source" ] null frameworkSystem;
frameworkNiriShutdownSource =
  lib.attrByPath [ "environment" "etc" "systemd/user/niri-shutdown.target" "source" ] null frameworkSystem;
```

Replace `niriUnstable` package identity checks with a guarded assertion:

```nix
{
  assertion =
    niriUpstream != null
    && toString razerNativeNiri.package == toString niriUpstream
    && toString frameworkNativeNiri.package == toString niriUpstream
    && toString razerSystem.programs.niri.package == toString niriUpstream
    && toString razerEmbeddedNativeNiri.package == toString niriUpstream;
  message = "Enabled Linux Niri consumers must share the official upstream derivation";
}
{
  assertion =
    inputs.niri.inputs.nixpkgs.outPath == inputs.nixpkgs.outPath
    && !(inputs.niri.inputs ? rust-overlay);
  message = "Official Niri must follow primary nixpkgs without retaining rust-overlay";
}
{
  assertion =
    niriUpstream != null
    && toString frameworkNiriServiceSource == "${niriUpstream}/lib/systemd/user/niri.service"
    && toString frameworkNiriShutdownSource == "${niriUpstream}/lib/systemd/user/niri-shutdown.target";
  message = "system-manager must install CachyOS Niri units from the official package";
}
```

- [ ] **Step 2: Verify the contract fails against epireyn**

Run:

```bash
rtk nix eval .#checks.x86_64-linux.configuration-contract.drvPath
```

Expected: failure because epireyn exposes `niri-unstable`, not `packages.x86_64-linux.niri`.

- [ ] **Step 3: Switch the input and consumers**

Change `flake.nix` to:

```nix
niri = {
  url = "github:niri-wm/niri";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

In `modules/home-manager/niri/default.nix` and `modules/system/niri.nix`, select:

```nix
inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri
```

Do not add a fallback, overlay, substituter, public key, or Darwin access to this package.

In `modules/system-manager/niri.nix`, add `pkgs` and `inputs` arguments and add this binding beside the existing `cfg` binding:

```nix
niriPackage = inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri;
```

Add these exact entries to the existing `lib.mkIf cfg.enable` body without changing its assertions, PAM files, greetd configuration, or service:

```nix
environment.etc."systemd/user/niri.service".source =
  "${niriPackage}/lib/systemd/user/niri.service";
environment.etc."systemd/user/niri-shutdown.target".source =
  "${niriPackage}/lib/systemd/user/niri-shutdown.target";
```

- [ ] **Step 4: Perform only the targeted lock update**

Run:

```bash
rtk nix flake update niri
rtk git diff -- flake.lock
rtk jq -e '.nodes.niri.locked.owner == "niri-wm" and .nodes.niri.locked.repo == "niri" and .nodes.niri.locked.rev == "e9b215fef4b11ad36776553fb8bd45118ef03b03"' flake.lock
niri_source="$(rtk nix eval --raw --impure --expr '(builtins.getFlake (toString ./.)).inputs.niri.outPath')"
rtk read "$niri_source/flake.nix"
rtk proxy sha256sum "$niri_source/Cargo.lock"
```

Expected: root `niri` changes from epireyn to `niri-wm/niri`, obsolete epireyn descendant lock nodes disappear, and no unrelated root input revision changes. The reviewed official `flake.nix` must build the checkout with its own `Cargo.lock`, derive the package version/build commit from the locked revision, and declare no binary cache. Stop if official main no longer resolves to the exact source commit; do not mix a source upgrade into this migration boundary.

- [ ] **Step 5: Format and evaluate the official package contract**

Run:

```bash
rtk nix fmt flake.nix parts/checks.nix modules/home-manager/niri/default.nix \
  modules/system/niri.nix modules/system-manager/niri.nix
rtk nix eval .#checks.x86_64-linux.configuration-contract.drvPath
rtk nix eval --raw --impure --expr '(builtins.getFlake (toString ./.)).inputs.niri.rev'
rtk nix eval --raw --impure --expr '(builtins.getFlake (toString ./.)).inputs.niri.packages.x86_64-linux.niri.version'
```

Expected: contract derivation path, full revision `e9b215fef4b11ad36776553fb8bd45118ef03b03`, and a package version derived from that revision.

- [ ] **Step 6: Force the exact package to build locally**

Run:

```bash
rtk nix build --no-link --rebuild --option substitute false --print-out-paths --impure \
  --expr '(builtins.getFlake (toString ./.)).inputs.niri.packages.x86_64-linux.niri'
```

Expected: the Niri derivation builds successfully without substituting the package output. Execute the returned store path's `bin/niri --version` with `rtk proxy` and confirm it reports the locked revision.

- [ ] **Step 7: Verify the system-manager units and package-only equivalence**

Build `.#systemConfigs.cachyos-framework13`, inspect both realized `/etc/systemd/user` sources, and compare their unit semantics with `/usr/lib/systemd/user/niri.service` and `niri-shutdown.target`. The official service intentionally uses an absolute selected-package `ExecStart`; all unit dependencies and shutdown behavior must otherwise match. Run the two source builds from Task 1 Step 10 again, then compare them with the stage-one generated files. Expected: no KDL behavior change; only package-derived store paths may change if the official package derivation path differs despite the identical source revision.

- [ ] **Step 8: Run all exact target evaluations**

Run:

```bash
rtk nix eval .#homeConfigurations.razer14.activationPackage.drvPath
rtk nix eval .#homeConfigurations.cachyos-framework13.activationPackage.drvPath
rtk nix eval .#nixosConfigurations.razer14.config.system.build.toplevel.drvPath
rtk nix eval .#nixosConfigurations.dell-plex.config.system.build.toplevel.drvPath
rtk nix eval .#darwinConfigurations.PNH46YXX3Y.config.system.build.toplevel.drvPath
rtk nix eval .#systemConfigs.cachyos-framework13.drvPath
rtk nix eval .#checks.x86_64-linux.configuration-contract.drvPath
```

Expected: all seven return derivation paths, and Darwin does not attempt to evaluate the Linux-only package.

- [ ] **Step 9: Commit the package migration**

Run:

```bash
rtk git status --short
rtk git add flake.nix flake.lock parts/checks.nix \
  modules/home-manager/niri/default.nix modules/system/niri.nix \
  modules/system-manager/niri.nix
rtk git diff --cached --check
rtk git diff --cached
rtk git commit -m "refactor: source Niri from upstream"
```

---

### Task 3: Resolve Exceptions and Complete Repository Validation

**Files:**
- Modify: `TODO.md`
- Test: `checks.x86_64-linux.configuration-contract`
- Test: both native Home Manager generated Niri sources
- Test: repository `just check`

**Interfaces:**
- Consumes: completed native module and official-package migrations.
- Produces: one historical resolution entry with exact provenance and validation evidence.
- Produces: a clean, reviewable feature branch with no activation side effects.

- [ ] **Step 1: Prove active configuration no longer references the fork**

Run:

```bash
rtk git grep -n -E 'epireyn|niri-unstable|niri-flake|niri-epireyn\.cachix|niri\.cachix' -- \
  flake.nix flake.lock 'parts/*.nix' 'modules/**/*.nix' 'users/**/*.nix'
```

Expected: no matches. Documentation history may still name the retired sources.

- [ ] **Step 2: Resolve the two active Niri exceptions**

Delete the first two active bullets in `TODO.md`. Keep the active `systemd.services.greetd.restartIfChanged = false` bullet unchanged. Add this exact resolution under `Resolved pinned exceptions`:

```markdown
- 2026-08-18: removed the third-party Niri module and package dependency. Original issue: this repository depended on sodiboo/epireyn's structured settings renderer and `config.lib.niri.actions`, and used epireyn's `niri-unstable` output to preserve the historical upstream-main, locally built Niri policy because Nixpkgs provided release 26.04 only. Resolution: the locked Home Manager contains native `wayland.windowManager.niri` support from merged PR #9685; every action helper and fork-specific settings shape was translated to direct KDL-shaped settings, and the Razer and Framework rendered configurations were compared and validated with the selected package. The `niri` input now follows canonical `github:niri-wm/niri` main, follows primary Nixpkgs, introduces no `rust-overlay`, and every enabled Linux consumer uses `inputs.niri.packages.${system}.niri` directly without an overlay, fallback, or third-party cache. NixOS session integration uses Nixpkgs `programs.niri`; system-manager retains native greetd/PAM integration and sources both CachyOS user units from that same official package. The migration preserved Niri source commit `e9b215fef4b11ad36776553fb8bd45118ef03b03` across the package-provider boundary. Affected outputs: `homeConfigurations.razer14`, `homeConfigurations.cachyos-framework13`, `nixosConfigurations.razer14`, `nixosConfigurations.dell-plex`, `darwinConfigurations.PNH46YXX3Y`, `systemConfigs.cachyos-framework13`, and `checks.x86_64-linux.configuration-contract`. Validation: all seven exact evaluations returned derivation paths, both old/new KDL pairs were reviewed for behavioral equivalence and validated by the exact package, the contract built, system-manager's two user units resolved from the exact package, the exact official package rebuilt with substitution disabled, removed-reference and formatting checks passed, and no activation ran.
```

- [ ] **Step 3: Build the contract and both validated KDL sources**

Run:

```bash
rtk nix build --no-link .#checks.x86_64-linux.configuration-contract
rtk nix build --no-link --impure --expr '(builtins.getFlake (toString ./.)).homeConfigurations.razer14.config.xdg.configFile."niri/config.kdl".source'
rtk nix build --no-link --impure --expr '(builtins.getFlake (toString ./.)).homeConfigurations.cachyos-framework13.config.xdg.configFile."niri/config.kdl".source'
```

Expected: all three builds succeed; both source derivations run `niri validate` from the exact official package.

- [ ] **Step 4: Run repository-wide non-activating checks**

Run:

```bash
rtk just check
rtk git diff --check
rtk git status --short
```

Expected: `just check` succeeds with only pre-existing upstream warnings, whitespace checks are clean, and only `TODO.md` remains uncommitted at this task boundary.

- [ ] **Step 5: Commit the resolved exception history**

Run:

```bash
rtk git add TODO.md
rtk git diff --cached --check
rtk git diff --cached
rtk git commit -m "docs: resolve Niri migration exceptions"
```

- [ ] **Step 6: Inspect the completed branch without activating it**

Run:

```bash
rtk git status --short --branch
rtk git log --oneline --decorate main..HEAD
rtk git diff --stat main...HEAD
rtk git diff --check main...HEAD
```

Expected: clean `feat/niri-native-home-manager` worktree with the design, plan, renderer migration, official package migration, and resolved TODO history. No switch or activation command appears in the execution log.
