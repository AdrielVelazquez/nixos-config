---
title: Recover a ZMK keymap from the nice!nano bootloader's CURRENT.UF2 before reflashing
date: 2026-11-11
category: tooling-decisions
module: keyboards/corne
problem_type: workflow_issue
component: tooling
severity: medium
applies_when:
- "The keyboard's on-device keymap is not in git and the firmware has no ZMK Studio serial port"
- "About to flash a Nix-built ZMK image over a board whose current layout is unknown"
tags: [zmk, nice-nano, keymap, backup, uf2, current-uf2, zmk-nix]
last_updated: 2026-11-11
---
# Recover a ZMK keymap from the nice!nano bootloader's CURRENT.UF2 before reflashing

## Context
The Corne's firmware did not expose a ZMK Studio serial port, so the live keymap could not be dumped over USB. Flashing a new image would have replaced the only copy of the running layout.

## Guidance
- Double-tap reset to enter the bootloader. Copy `CURRENT.UF2` from the drive to a safe location before flashing anything. It is the full flash image (about 1.3 MB) and changes nothing on the keyboard.
- Convert the UF2 to a flat binary by reading each 512-byte block's `targetAddr` and payload. The app starts at `0x26000` on nice!nano v2 (the bootloader and SoftDevice sit below it).
- Locate the keymap by its behavior name pointers. Each binding is a struct whose first word points to a behavior name string such as `key_press`, `momentary_layer`, `bluetooth` or `transparent`. Scan for those pointers, then read the records at a fixed stride:
  - 12 bytes (`name`, `param1`, `param2`) for the firmware that had no Studio.
  - 16 bytes for the Studio build (an extra word per record). A stride check alone identifies which layout you have.
- Decode `key_press` params as ZMK keycodes: the low 16 bits are the HID usage (`0x07` page) and the high byte holds modifier flags (`0x02` = LSHIFT, so `LSFT(0x1e)` is `!`).
- Hold-tap timings live in each behavior's config struct, reachable from the device struct listed beside the name table. The first word is `tapping-term-ms`, and the flavor enum sits at offset 20.

## Why This Matters
Reading back `CURRENT.UF2` is the only non-destructive way to capture an unflashed layout. Without it, reflashing from git would silently replace whatever layout is actually loaded. The decoded layer 2 showed `LSFT(LBKT)` where the repo bound `LBRC`, so a visual comparison with the repo would have missed a real mismatch.

Verify by re-decoding the new build's UF2 with the same method and comparing binding-by-binding. Do not trust a diff of the decoded table against a second decode of the same file: a shared path or base address can make both sides identical.

## When to Apply
- Before flashing any ZMK image onto a board that has no Studio serial port.
- When repo and device behavior disagree and you need the device's actual bindings.
