# Framework 13 Apple Studio Display Troubleshooting

This document records reusable diagnostics for intermittent Apple Studio
Display flicker or black screens on a Framework 13 AMD laptop running CachyOS
and Niri. The observed failure is a real DisplayPort hotplug/link drop, not only
a compositor layout change.

## Symptoms And Baseline

The expected steady state is a native `5120x2880@60` external output, with any
phantom duplicate connector disabled. During flicker, the active DisplayPort
connector disappears and returns, and kernel logs show AMD hot-plug callbacks.

Discover current connector names instead of assuming a stable `DP-*` number:

```bash
niri msg --json outputs
sudo find /sys/kernel/debug/dri -path '*DP-*/link_settings' -print
```

Collect compositor and kernel evidence around an event:

```bash
journalctl --user -b -u niri.service -o short-iso --since '15 minutes ago' --no-pager
journalctl --user -b -u niri-internal-display-auto-off.service -o short-iso --since '15 minutes ago' --no-pager
journalctl -b -k -o short-iso --since '15 minutes ago' --no-pager
```

Look for connector disconnect/reconnect events, AMD HPD callbacks, `DPIA AUX
failed`, USB hub removal, Thunderbolt device removal, retimer errors, and UCSI
errors. A simultaneous retimer, Thunderbolt, USB hub, and display disconnect is
stronger evidence of a USB4 path reset than a display-mode issue alone.

## Mode Change Limitation

Forcing a 4K mode was not a reliable workaround. On the tested setup it turned
the display off and produced errors similar to:

```text
DPIA AUX failed
enabling link failed
```

Returning the connector to automatic mode recovered it:

```bash
CONNECTOR=DP-7
niri msg output "$CONNECTOR" mode auto
```

Do not assume a lower resolution avoids the underlying USB4 or DisplayPort
link failure.

## HBR3 Evidence

The connector initially trained at HBR2 even though HBR3 was reported and
verified. A representative `link_settings` state was:

```text
Current:   4 0x14 0
Verified:  4 0x1e 16
Reported:  4 0x1e 16
Preferred: 0 0x0 0
```

Here, `0x14` is HBR2 and `0x1e` is HBR3. After setting HBR3 as preferred and
reconnecting the display, the current link trained at HBR3:

```text
Current:   4 0x1e 0
Verified:  4 0x1e 16
Reported:  4 0x1e 16
Preferred: 4 0x1e 0
```

Inspect the discovered connector path before writing anything:

```bash
DRI_DEVICE=1
CONNECTOR=DP-7
sudo cat "/sys/kernel/debug/dri/$DRI_DEVICE/$CONNECTOR/link_settings"
```

A manual write is state-changing and can blank the display until reconnect:

```bash
DRI_DEVICE=1
CONNECTOR=DP-7
printf '%s\n' '4 0x1e 16' | sudo tee "/sys/kernel/debug/dri/$DRI_DEVICE/$CONNECTOR/link_settings"
```

Only consider this when the connector reports or verifies HBR3 support. Do not
copy a PCI device or connector name from another machine.

HBR3 reduced dependence on the suspected HBR2 plus DSC path, but flickers still
occurred while the link remained at HBR3. Treat forcing HBR3 as a partial
stabilizer, not a proven fix.

## USB4 And Thunderbolt Evidence

Some events only showed DisplayPort hotplug callbacks. Other events removed the
retimer, Thunderbolt device, USB hub, and display together. The latter pattern
supports investigating USB4 retimer, authorization, and power-state behavior.

Useful runtime checks:

```bash
grep -o 'thunderbolt.host_reset=[^ ]*' /proc/cmdline || true
command -v boltctl || true
systemctl status bolt.service
journalctl -b -k --no-pager | grep -Ei 'thunderbolt|usb4|retimer|ucsi|dpia|hpd'
```

Potential mitigations seen in comparable configurations include loading the
Thunderbolt module early, enabling Bolt authorization, and setting
`thunderbolt.host_reset=false`. These require host-specific testing and a
reboot or module reload. They are hypotheses, not proven universal fixes.

## Upstream References

- CachyOS forum report describing HBR2 plus DSC instability and an HBR3
  workaround:
  <https://discuss.cachyos.org/t/fix-apple-studio-display-5k-flicker-black-screen-on-linux-with-amd-macbookpro16-1-by-forcing-displayport-hbr3-and-avoiding-dsc/29495>
- Framework community report connecting Studio Display flicker with USB4
  retimer or PCIe power-state failures:
  <https://community.frame.work/t/apple-studio-display-flickers-after-firmware-update-to-0-0-3-5/82587>
- EDID override example, useful when native modes are detected incorrectly:
  <https://github.com/jwilger/nixos-config/blob/63c2eeee114adffb2076b6afdd5f1ae4240b0232/modules/hardware/edid-apple-studio-display.nix>
- Thunderbolt initialization and Bolt comparison:
  <https://github.com/arne/nixcfg/blob/a04c9b466ba1e473dbfcaab89a82071875e7a53e/hosts/fox/configuration.nix>
- Bolt configuration mentioning Studio Display USB HID:
  <https://github.com/supermarin/dotfiles/blob/08499e43efc3377ad2e963eb5ea80d76514bd5bb/nixos/configuration.nix>
- AMD Strix Point tile mismatch comparison:
  <https://github.com/stamp711/nix/blob/fe33b23ebe27ad6080c14a3268ac46dd5fc2e690/hosts/personal/gpd/hardware.nix>

An EDID override is most relevant when resolution or mode detection is wrong.
It is not the leading fix when native 5K mode is already detected and logs show
a full connector or USB4 path drop.

## Testing On Other Hosts

Do not apply the Framework workaround to another machine without first
discovering its debugfs connector and checking `Current`, `Verified`,
`Reported`, and `Preferred`. Consider an equivalent HBR3 workaround only when
that host also trains at HBR2 while reporting or verifying HBR3 support.
