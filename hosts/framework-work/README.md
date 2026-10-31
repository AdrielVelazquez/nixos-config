# Framework work laptop — NixOS

`nixosConfigurations.framework-work` is a fresh-install alternative for the
Framework Laptop 13 AMD Ryzen AI 300 Series. It embeds Home Manager for login
`adriel` (`/home/adriel`), sharing `users/adriel-work` with the existing
CachyOS Home Manager target. CachyOS outputs are retained for migration later.

**This is a prepared configuration, not a workplace-approved migration.** No
installation or activation is performed by adding/building this host.

## Before migrating

- Back up the entire current machine and test recovery, including your home,
  browser profiles, SSH/authentication material, and both system/user SOPS age
  keys. Do not put private keys or decrypted secrets in this repository.
- Obtain workplace approval and resolve **Falcon Sensor and Duo Desktop
  installation/enrollment** on NixOS. Existing resource-limit drop-ins do not
  install either agent; `duo-unix` is not a substitute for Duo Desktop.
- Confirm Fleet server compatibility, enrollment and policy checks, WARP
  enrollment/SSO access, and the organization's encryption/recovery policy.
  Fleet's [NixOS guide](https://fleetdm.com/guides/enroll-hosts#enroll-nixos-hosts)
  currently says disk-encryption key escrow is not supported. Local LUKS
  encryption is not proof of policy compliance or recovery-key escrow.
- Arrange temporary SSH authentication for the private flake inputs during
  installation. Do not embed credentials or SSH private keys in Nix files.
- Review storage and the host's display/USB4 workarounds. Firmware, hardware
  behavior, agent connectivity, and suspend/resume require post-install tests.

## Storage

`disko.nix` defines a **destructive fresh-disk** layout:

- 1 GiB EFI partition at `/boot`.
- Remaining disk in passphrase-protected `cryptframework` (LUKS).
- LVM group `framework`: 80 GiB swap and remaining space as ext4 root.
- Resume device `/dev/framework/swap`; root and swap share the persistent
  encryption container. Zram has higher normal swap priority and is not used
  for hibernation. The swap size targets this machine's 64 GiB RAM; revisit it
  if the hardware changes.

The disk device deliberately defaults to a nonexistent
`/dev/disk/by-id/REPLACE-WITH-FRAMEWORK-INSTALL-DISK`. Evaluation/build works
without choosing a disk; formatting will not work until you explicitly replace
that value. **This is not an in-place conversion or dual-boot layout.**

## Validate without activation

From a checkout with access to the private inputs:

```bash
nix eval --no-write-lock-file .#nixosConfigurations.framework-work.config.system.build.toplevel.drvPath
nix build --no-link .#checks.x86_64-linux.framework-work-contract .#checks.x86_64-linux.snoocert-bundle
nix build --dry-run --no-link .#nixosConfigurations.framework-work.config.system.build.toplevel
```

These commands do not change the running system or format a disk. A dry-run
only plans the build; evaluation and package builds do not establish that the
laptop boots or workplace agents work.

## Fresh installation — only when ready

Use a NixOS x86_64 UEFI installer, with network and private-input authentication
available. Clone/check out the reviewed branch. Inspect `lsblk -f` and
`/dev/disk/by-id/`, then edit **only** the selected install disk's `device` in
`hosts/framework-work/disko.nix`. Verify its model, capacity, and identity;
never select a disk solely from an assumed `/dev/nvme0n1` name.

Re-evaluate the exact host after that edit and build the pinned disko script:

```bash
nix build .#nixosConfigurations.framework-work.config.system.build.diskoScript -o /tmp/framework-work-disko
```

**The following command erases the selected disk and mounts the new
filesystems under `/mnt`. It destroys CachyOS and all data on that disk.
Do not run it until backups, workplace approval, disk selection, and the
migration blockers above are resolved.**

```bash
sudo /tmp/framework-work-disko
```

Choose a strong LUKS passphrase and keep an offline recovery copy according to
workplace policy. This configuration does not enable TPM unlock or Secure Boot.
Do not assume the unencrypted EFI partition has verified-boot protection.

Restore the existing age keys from your secure backup to the target filesystem
**outside the Nix store**, creating directories with mode `0700` and key files
with mode `0600`:

- `/mnt/var/lib/sops/age/keys.txt` — system Fleet enrollment and corporate CA.
- `/mnt/home/adriel/.config/sops/age/keys.txt` — existing Home Manager secrets.
  Ensure this key and its directories belong to `adriel` after account creation.

Then install the selected flake from the installer:

```bash
sudo nixos-install --flake .#framework-work --no-root-passwd
sudo nixos-enter --root /mnt -c 'passwd adriel'
```

**These commands install the OS and change an account password.** There is no
plaintext/default user password in the configuration; setting `adriel`'s
password before reboot is essential. The mutable account database preserves
this password on subsequent rebuilds. Check key ownership, `/mnt/etc/fstab`,
boot entries, and the completed installation before manually rebooting.
Keep the installer/recovery media available.

## After boot

Verify these boundaries before using the laptop for work:

- `findmnt /`, `lsblk -f`, `swapon --show`, and
  `/sys/power/resume`: root and resume swap are inside LUKS.
- Login, `sudo`, Niri, hyprlock unlock, keyboard remaps, and external keyboards.
- `systemctl status sops-install-secrets snoocert-trust orbit cloudflare-warp`
  and the Fleet host record/scripts/Desktop tray. Do not print enrollment
  secrets into diagnostics. WARP still requires your organization's enrollment.
- The runtime CA bundle `/run/snoocert/ca-bundle.crt` and user NSS trust. It is
  assembled from the public CA bundle plus the SOPS certificate at boot;
  missing/invalid corporate certificate causes the trust service to fail,
  rather than placing decrypted corporate material in a build artifact.
- Audio, Bluetooth, screen sharing/recording, Wi-Fi across suspend/resume,
  lid/dock behavior, and an explicitly supervised hibernate/resume cycle.
- Studio Display brightness, native 5K mode, hotplug, and USB4 stability. The
  retained HBR3/host-reset/AMD workarounds are not a guarantee of a full fix.
- Both workplace endpoint agents and required security policies, including
  recovery-key handling. Resolve all failures before declaring migration done.

## Later rebuilds

On this **already installed NixOS host**, `just bootstrap framework-work` or
`just switch framework-work` changes the running system. Neither command is a
fresh-disk installer. Home Manager is embedded: do not additionally activate
`homeConfigurations.cachyos-framework13` on this host.

Fleet Orbit/Desktop are selected only for this host by
`packages/fleet-official.nix`; CachyOS keeps its existing Fleet fork. Updates
are declarative, not Fleet self-updates. Fleet cannot deploy ordinary software
packages to this NixOS host; manage them through Nix. See `TODO.md` for removal
criteria for the package pin and outstanding migration gates.
