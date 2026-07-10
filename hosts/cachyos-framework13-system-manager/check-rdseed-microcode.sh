#!/usr/bin/env bash
set -euo pipefail

# Verify whether the RDSEED (AMD-SB-7055 / CVE-2025-62626) microcode fix is
# present in the initramfs that Limine actually loads on this Framework 13
# (AMD Ryzen AI 9 HX 370 / Strix Point, family 0x1a model 0x24 stepping 0).
#
# The Linux kernel (arch/x86/kernel/cpu/amd.c, zen5_rdseed_microcode[]) requires
# microcode revision >= 0x0b204037 for this model. Anything older trips the
# "RDSEED32 is broken" message at boot. 0x0b20401b is the older, unpatched rev.
#
# The fixed microcode ships in linux-firmware/amd-ucode and the mkinitcpio
# `microcode` hook embeds it as an uncompressed early-CPIO at the front of the
# initramfs. The companion parser reads the AuthenticAMD.bin CPIO member and
# validates structured AMD patch headers instead of searching arbitrary bytes.
#
# Usage:
#   ./check-rdseed-microcode.sh          # read-only verification
#   ./check-rdseed-microcode.sh --fix    # reinstall kernels first, then verify
#   ./check-rdseed-microcode.sh --self-test
#
# WARNING: --fix is state-changing. It reinstalls kernels and regenerates
# initramfs and Limine boot artifacts. Ensure a recoverable boot path exists.

FIXED_REV=0x0b204037
OLD_REV=0x0b20401b
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SCANNER="$SCRIPT_DIR/check-rdseed-microcode.py"

case "${1:-}" in
  "") ;;
  --fix) ;;
  --self-test)
    exec python3 "$SCANNER" --self-test
    ;;
  *)
    echo "usage: $0 [--fix|--self-test]" >&2
    exit 2
    ;;
esac

run_sudo() {
  if [[ $EUID -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

if [[ "${1:-}" == "--fix" ]]; then
  echo "WARNING: --fix will reinstall kernels and modify installed boot artifacts."
  echo "##### reinstalling kernels (fires mkinitcpio + Limine deploy hooks) #####"
  run_sudo pacman -S --noconfirm linux-cachyos linux-cachyos-lts
  echo
fi

echo "##### running state (no sudo needed) #####"
grep -m1 -i microcode /proc/cpuinfo || true
if boot_journal=$(journalctl -b 0 --no-pager 2>/dev/null); then
  journal_status=0
else
  journal_status=$?
fi
printf '%s' "$boot_journal" | python3 "$SCANNER" journal-status "$journal_status"
if [[ $journal_status -eq 0 ]]; then
  printf '%s\n' "$boot_journal" | grep -iE "microcode: (Updated|Current)" || true
else
  echo "microcode journal lines: unavailable"
fi
echo

echo "##### limine.conf #####"
for c in /boot/limine.conf /boot/limine/limine.conf /boot/EFI/limine/limine.conf; do
  if run_sudo test -f "$c"; then
    echo "--- $c ---"
    run_sudo cat "$c"
  fi
done
echo

echo "##### BLS entries #####"
for e in /boot/loader/entries/*.conf; do
  if run_sudo test -f "$e"; then
    echo "--- $e ---"
    run_sudo cat "$e"
  fi
done
echo

echo "##### structured initrd AMD microcode scan #####"
run_sudo python3 "$SCANNER" scan /boot "$FIXED_REV" "$OLD_REV"
echo
echo "Expected after a working fix: the image referenced by limine.conf / the"
echo "booted BLS entry shows fixed_${FIXED_REV}=YES."
