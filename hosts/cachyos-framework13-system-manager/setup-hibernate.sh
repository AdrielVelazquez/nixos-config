#!/usr/bin/env bash
set -euo pipefail

# One-time setup for disk-backed hibernate on the Framework 13 CachyOS host.
# This keeps zram as preferred day-to-day swap and adds a persistent swapfile
# plus the kernel resume parameters needed for hibernation after power-off.
#
# WARNING: This script creates and activates swap, appends to /etc/fstab,
# writes boot parameters, and runs limine-update. Review it before execution.

ASSUME_YES=false
SWAP_SIZE_ARG=""

for arg in "$@"; do
  case "$arg" in
    -y | --yes)
      ASSUME_YES=true
      ;;
    -h | --help)
      echo "usage: $0 [--yes] [SIZE]"
      echo "  --yes  skip the interactive confirmation"
      echo "  SIZE   swapfile size, for example 80G"
      exit 0
      ;;
    -*)
      echo "Unknown option: $arg" >&2
      exit 2
      ;;
    *)
      if [[ -n $SWAP_SIZE_ARG ]]; then
        echo "Only one swapfile size may be specified." >&2
        exit 2
      fi
      SWAP_SIZE_ARG=$arg
      ;;
  esac
done

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

run_sudo() {
  if [[ $EUID -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

default_swap_size() {
  local mem_gib
  mem_gib=$(awk '/MemTotal/ { print int(($2 / 1024 / 1024) + 0.999999) }' /proc/meminfo)
  echo "$((mem_gib + 8))G"
}

size_to_mib() {
  local bytes
  bytes=$(numfmt --from=iec "$1")
  echo $(((bytes + 1048575) / 1048576))
}

swapfile_active() {
  run_sudo swapon --show=NAME --noheadings 2>/dev/null | awk '{ print $1 }' | grep -Fxq "$SWAPFILE"
}

fstab_has_swapfile() {
  awk -v target="$SWAPFILE" '
    $1 == target && $2 == "none" && $3 == "swap" { found = 1 }
    END { exit(found ? 0 : 1) }
  ' /etc/fstab
}

strip_resume_params() {
  printf '%s\n' "$1" | sed -E \
    -e 's/(^|[[:space:]])resume=[^[:space:]]+//g' \
    -e 's/(^|[[:space:]])resume_offset=[^[:space:]]+//g' \
    -e 's/[[:space:]]+/ /g' \
    -e 's/^ //; s/ $//'
}

base_cmdline() {
  if run_sudo test -f /etc/kernel/cmdline; then
    run_sudo sed -n '1p' /etc/kernel/cmdline
  else
    sed -n '1p' /proc/cmdline
  fi
}

update_limine_defaults() {
  local path=$1
  local full_cmdline=$2
  local backup tmp_in tmp_out line indent operator value quoted updated

  backup="${path}.bak.$(date +%Y%m%d%H%M%S)"
  tmp_in=$(mktemp)
  tmp_out=$(mktemp)
  updated=0

  run_sudo cp "$path" "$backup"
  run_sudo cp "$path" "$tmp_in"

  while IFS= read -r line; do
    if [[ $line =~ ^([[:space:]]*)KERNEL_CMDLINE\[default\](\+?=)(.*)$ ]]; then
      indent="${BASH_REMATCH[1]}"
      operator="${BASH_REMATCH[2]}"
      value="${BASH_REMATCH[3]}"
      quoted=0

      if [[ $value == \"*\" && $value == *\" ]]; then
        quoted=1
        value="${value:1:${#value}-2}"
      fi

      value=$(strip_resume_params "$value")
      if [[ -n $value ]]; then
        value="${value} resume=UUID=${ROOT_UUID} resume_offset=${RESUME_OFFSET}"
      else
        value="resume=UUID=${ROOT_UUID} resume_offset=${RESUME_OFFSET}"
      fi

      if [[ $quoted -eq 1 || $operator == "+=" ]]; then
        printf '%sKERNEL_CMDLINE[default]%s"%s"\n' "$indent" "$operator" "$value" >> "$tmp_out"
      else
        printf '%sKERNEL_CMDLINE[default]%s%s\n' "$indent" "$operator" "$value" >> "$tmp_out"
      fi
      updated=1
    else
      printf '%s\n' "$line" >> "$tmp_out"
    fi
  done < "$tmp_in"

  if [[ $updated -eq 0 ]]; then
    printf '\nKERNEL_CMDLINE[default]="%s"\n' "$full_cmdline" >> "$tmp_out"
  fi

  run_sudo install -m 644 "$tmp_out" "$path"
  rm -f "$tmp_in" "$tmp_out"

  echo "==> Updated ${path}"
  echo "    Backup: ${backup}"
}

write_kernel_cmdline() {
  local path=/etc/kernel/cmdline
  local full_cmdline=$1
  local backup

  if run_sudo test -f "$path"; then
    backup="${path}.bak.$(date +%Y%m%d%H%M%S)"
    run_sudo cp "$path" "$backup"
    echo "==> Backed up ${path}"
    echo "    Backup: ${backup}"
  fi

  printf '%s\n' "$full_cmdline" | run_sudo tee "$path" >/dev/null
  echo "==> Wrote ${path}"
}

for cmd in awk dd filefrag findmnt grep limine-update mkswap numfmt sed swapon; do
  need_cmd "$cmd"
done

SWAPFILE="${SWAPFILE:-/swapfile-hibernate}"
DEFAULT_SWAP_SIZE=$(default_swap_size)
SWAP_SIZE="${SWAP_SIZE_ARG:-${SWAP_SIZE:-$DEFAULT_SWAP_SIZE}}"
SWAP_PRIORITY="${SWAP_PRIORITY:-1}"
ROOT_FSTYPE=$(findmnt -no FSTYPE /)

echo "WARNING: this will modify swap, /etc/fstab, and boot parameters."
echo "Review the detected values below before allowing sudo operations."

if [[ $ROOT_FSTYPE != "ext4" ]]; then
  echo "This script expects an ext4 root filesystem. Detected: ${ROOT_FSTYPE}" >&2
  echo "Use a swap partition or adapt the swapfile steps manually for your filesystem." >&2
  exit 1
fi

if ! grep -Eq '^HOOKS=.*\bsystemd\b' /etc/mkinitcpio.conf; then
  echo "This script expects mkinitcpio's systemd hook in /etc/mkinitcpio.conf." >&2
  echo "If you use non-systemd hooks, wire resume support manually before rebuilding the initramfs." >&2
  exit 1
fi

existing_non_zram_swap=$(
  run_sudo swapon --show=NAME --noheadings 2>/dev/null | awk '
    $1 !~ /^\/dev\/zram/ && $1 != "" { print $1 }
  '
)

if [[ -n $existing_non_zram_swap && $existing_non_zram_swap != "$SWAPFILE" ]]; then
  echo "Found an existing non-zram swap device: ${existing_non_zram_swap}" >&2
  echo "This script only automates the swapfile path. Reuse that device manually instead." >&2
  exit 1
fi

echo "==> Root filesystem: ${ROOT_FSTYPE}"
echo "==> Hibernate swapfile: ${SWAPFILE}"
echo "==> Requested size: ${SWAP_SIZE}"

if [[ $ASSUME_YES != true ]]; then
  if [[ ! -t 0 ]]; then
    echo "Refusing to modify the system without confirmation." >&2
    echo "Run interactively or pass --yes after reviewing the detected values." >&2
    exit 1
  fi

  read -r -p "Type 'yes' to modify swap, fstab, and boot parameters: " response
  if [[ $response != "yes" ]]; then
    echo "Cancelled; no changes made."
    exit 0
  fi
fi

if run_sudo test -e "$SWAPFILE"; then
  if swapfile_active || fstab_has_swapfile; then
    echo "==> Reusing existing ${SWAPFILE}"
  else
    echo "Refusing to overwrite existing ${SWAPFILE}" >&2
    echo "Remove it first or rerun with SWAPFILE=/some/other/path." >&2
    exit 1
  fi
else
  echo "==> Creating ${SWAPFILE}..."
  SWAP_SIZE_MIB=$(size_to_mib "$SWAP_SIZE")
  run_sudo dd if=/dev/zero of="$SWAPFILE" bs=1M count="$SWAP_SIZE_MIB" status=progress conv=fsync
  run_sudo chmod 600 "$SWAPFILE"
  run_sudo mkswap "$SWAPFILE"
fi

if ! fstab_has_swapfile; then
  echo "==> Adding ${SWAPFILE} to /etc/fstab..."
  printf '%s none swap defaults,pri=%s 0 0\n' "$SWAPFILE" "$SWAP_PRIORITY" | run_sudo tee -a /etc/fstab >/dev/null
fi

if ! swapfile_active; then
  echo "==> Activating ${SWAPFILE}..."
  run_sudo swapon "$SWAPFILE"
fi

ROOT_UUID=$(findmnt -no UUID -T "$SWAPFILE")
RESUME_OFFSET=$(
  run_sudo filefrag -v "$SWAPFILE" | awk '
    $1 == "0:" {
      match($4, /^[0-9]+/)
      print substr($4, RSTART, RLENGTH)
      exit
    }
  '
)

if [[ -z $ROOT_UUID || -z $RESUME_OFFSET ]]; then
  echo "Failed to detect the resume UUID or resume offset." >&2
  exit 1
fi

echo "==> Discovered resume filesystem UUID and swapfile offset."

FULL_CMDLINE=$(strip_resume_params "$(base_cmdline)")
if [[ -n $FULL_CMDLINE ]]; then
  FULL_CMDLINE="${FULL_CMDLINE} resume=UUID=${ROOT_UUID} resume_offset=${RESUME_OFFSET}"
else
  FULL_CMDLINE="resume=UUID=${ROOT_UUID} resume_offset=${RESUME_OFFSET}"
fi

if run_sudo test -f /etc/default/limine; then
  echo "==> Updating /etc/default/limine..."
  update_limine_defaults /etc/default/limine "$FULL_CMDLINE"
else
  echo "==> Writing /etc/kernel/cmdline..."
  write_kernel_cmdline "$FULL_CMDLINE"
fi

echo "==> Regenerating Limine boot entries..."
run_sudo limine-update

echo
echo "Hibernate setup is in place. Reboot so the new kernel command line takes effect."
echo "After reboot, verify with:"
echo "  swapon --show"
echo "  busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanHibernate"
echo "If CanHibernate returns yes, test with: systemctl hibernate"
