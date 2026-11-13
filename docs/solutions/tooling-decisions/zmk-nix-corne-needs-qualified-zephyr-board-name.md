---
title: zmk-nix Corne build needs the qualified Zephyr board name, not nice_nano_v2
date: 2026-11-11
category: tooling-decisions
module: keyboards/corne
problem_type: build_error
component: tooling
severity: medium
applies_when:
- "Building ZMK firmware with zmk-nix buildSplitKeyboard/buildKeyboard for a nice!nano v2 controller"
- "Copying a board name from a ZMK GitHub Actions build.yaml into a Nix build"
tags: [zmk, zmk-nix, corne, nice-nano, zephyr, board-name, nix]
last_updated: 2026-11-11
---
# zmk-nix Corne build needs the qualified Zephyr board name, not nice_nano_v2

## Context
The Corne firmware lives in `AdrielVelazquez/zmk-config` and builds in GitHub Actions with `board: nice_nano_v2` in `build.yaml`. Vendoring it into `keyboards/corne/default.nix` with `board = "nice_nano_v2"` failed in the Nix build: CMake reported `Invalid BOARD; see above` for both halves.

## Guidance
- Use `board = "nice_nano@2.0.0//zmk";` with `buildSplitKeyboard`. That is the form zmk-nix's own `nix/firmware.nix` uses, and it built both `corne_left` and `corne_right` (`zmk.uf2`, 513024 and 379904 bytes).
- Keep `shield = "corne_%PART%";` and `enableZmkStudio` on the central part only; zmk-nix applies the Studio snippet to the central part and disables it for the peripheral.
- The first build fails with a fixed-output hash mismatch for `corne-firmware-west-deps`; paste the `got:` value into `zephyrDepsHash`. The placeholder `lib.fakeHash` is not a valid value for the final build.

## Why This Matters
The GitHub Actions board name works because the ZMK build workflow resolves it itself. The Nix path calls the Zephyr board directly, so the same name fails there with no hint about the alias. Not verified: the exact upstream reason (ZMK/Zephyr board rename or alias) — only the failing and passing builds were observed.

## When to Apply
- Porting any ZMK config from GitHub Actions to a zmk-nix build.
- Changing the controller board in `keyboards/corne/default.nix`.
