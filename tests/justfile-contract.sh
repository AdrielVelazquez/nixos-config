#!/usr/bin/env bash
set -euo pipefail

repo_root=${1:?usage: justfile-contract.sh REPOSITORY}
cd "$repo_root"

expect_missing_target() {
  local recipe=$1
  if just --dry-run "$recipe" >/dev/null 2>&1; then
    echo "Expected '$recipe' to reject a missing target" >&2
    exit 1
  fi
}

expect_rendered() {
  local expected=$1
  shift
  local output
  output=$(just --dry-run "$@" 2>&1)
  case "$output" in
    *"$expected"*) ;;
    *)
      echo "Expected 'just --dry-run $*' to contain: $expected" >&2
      echo "$output" >&2
      exit 1
      ;;
  esac
}

just --list >/dev/null

for recipe in \
  switch switch-trace build test dry-run diff \
  home-switch home-build \
  darwin-switch darwin-build \
  system-manager-switch
do
  expect_missing_target "$recipe"
done

expect_rendered "--flake .#razer14" switch razer14
expect_rendered "--flake .#razer14 --show-trace" switch-trace razer14
expect_rendered "--flake .#dell-plex" build dell-plex
expect_rendered "--flake .#razer14" test razer14
expect_rendered "--flake .#razer14" dry-run razer14
expect_rendered "--flake .#dell-plex" diff dell-plex
expect_rendered "--flake .#razer14" home-switch razer14
expect_rendered "--flake .#cachyos-framework13" home-build cachyos-framework13
expect_rendered "--flake .#PNH46YXX3Y" darwin-switch PNH46YXX3Y
expect_rendered "--flake .#PNH46YXX3Y" darwin-build PNH46YXX3Y
expect_rendered "--flake '.#cachyos-framework13'" system-manager-switch cachyos-framework13
expect_rendered "homeConfigurations.cachyos-framework13.activationPackage" home-activate-cachyos
expect_rendered "--flake '.#cachyos-framework13'" bootstrap-cachyos
