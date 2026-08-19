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

expect_missing_recipe() {
  local recipe=$1
  if just --show "$recipe" >/dev/null 2>&1; then
    echo "Expected '$recipe' recipe to be absent" >&2
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
  system-manager-eval system-manager-build system-manager-switch
do
  expect_missing_target "$recipe"
done

expect_rendered "--flake .#razer14" switch razer14
expect_rendered "--flake .#razer14 --show-trace" switch-trace razer14
expect_rendered "--flake .#razer14" build razer14
expect_rendered "--flake .#razer14" test razer14
expect_rendered "--flake .#razer14" dry-run razer14
expect_rendered "--flake .#razer14" diff razer14
expect_rendered "--flake .#cachyos-framework13" home-switch cachyos-framework13
expect_rendered "--flake .#cachyos-framework13" home-build cachyos-framework13
expect_missing_recipe darwin-switch
expect_missing_recipe darwin-build
expect_rendered \
  "nix eval '.#systemConfigs.cachyos-framework13.drvPath'" \
  system-manager-eval cachyos-framework13
expect_rendered \
  "nix build '.#systemConfigs.cachyos-framework13' --no-link" \
  system-manager-build cachyos-framework13
expect_rendered "--flake '.#cachyos-framework13'" system-manager-switch cachyos-framework13
expect_rendered "homeConfigurations.cachyos-framework13.activationPackage" home-activate-cachyos
expect_rendered "--flake '.#cachyos-framework13'" bootstrap-cachyos

fast_checks=$(just --dry-run check-fast 2>&1)
for check_name in \
  configuration-contract \
  nix-format \
  shell-syntax \
  justfile-contract \
  orbit-secret-path-contract \
  snoocert-trust \
  waybar-audio-actions
do
  case "$fast_checks" in
    *".#checks.x86_64-linux.$check_name"*) ;;
    *)
      echo "check-fast must build $check_name" >&2
      exit 1
      ;;
  esac
done

case "$fast_checks" in
  *".#checks.x86_64-linux.razer14"*)
    echo "check-fast must not build the CUDA-heavy Razer host" >&2
    exit 1
    ;;
esac

orbit_migration=$(just --dry-run migrate-cachyos-orbit 2>&1)
case "$orbit_migration" in
  *"/usr/bin/pacman -R"*) ;;
  *)
    echo "Orbit migration must render native package removal" >&2
    exit 1
    ;;
esac
case "$orbit_migration" in
  *"--noconfirm"*)
    echo "Orbit migration must remain interactive" >&2
    exit 1
    ;;
esac

bootstrap_output=$(just --dry-run bootstrap-cachyos 2>&1)
case "$bootstrap_output" in
  *"/usr/bin/pacman -R"*)
    echo "Framework bootstrap must not migrate Orbit implicitly" >&2
    exit 1
    ;;
esac

expect_rendered \
  "sudo /nix/var/nix/profiles/default/bin/nix --extra-experimental-features" \
  system-manager-switch cachyos-framework13
expect_rendered \
  "sudo /nix/var/nix/profiles/default/bin/nix-collect-garbage -d" \
  gc
expect_rendered \
  "sudo /nix/var/nix/profiles/default/bin/nix-collect-garbage --delete-older-than 7d" \
  gc-older 7
expect_rendered \
  "sudo /nix/var/nix/profiles/default/bin/nix-store --optimise" \
  optimize

for recipe_output in \
  "$(just --dry-run system-manager-switch cachyos-framework13 2>&1)" \
  "$(just --dry-run bootstrap-cachyos 2>&1)" \
  "$(just --dry-run gc 2>&1)" \
  "$(just --dry-run gc-older 7 2>&1)" \
  "$(just --dry-run optimize 2>&1)"
do
  case "$recipe_output" in
    *'sudo env "PATH=$PATH"'*)
      echo "Root Nix commands must not forward the caller PATH" >&2
      exit 1
      ;;
  esac
done
