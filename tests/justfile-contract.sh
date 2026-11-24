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

check_update_auth() (
  local fixture output bash_path
  bash_path=$(command -v bash)
  fixture=$(mktemp -d)
  trap 'rm -rf -- "$fixture"' EXIT
  {
    printf '#!%s\n' "$bash_path"
    cat <<'EOF'
set -eu
[[ $1 == '--why=Running just task for nixos' && $2 == --who=just && $3 == --mode=block ]]
shift 3
exec "$@"
EOF
  } > "$fixture/systemd-inhibit"
  {
    printf '#!%s\n' "$bash_path"
    cat <<'EOF'
set +x
set -eu
printf 'fake Nix reached\n'
[[ $# -ge 2 && $1 == flake && $2 == update ]]
[[ ${NIX_CONFIG:-} == "$EXPECT_NIX_CONFIG" ]]
[[ ${*:3} == "$EXPECT_INPUT" ]]
EOF
  } > "$fixture/nix"
  chmod +x "$fixture/nix" "$fixture/systemd-inhibit"
  export PATH="$fixture:$PATH"
  export NIX_CONFIG='warn-dirty = false' EXPECT_INPUT=''
  export EXPECT_NIX_CONFIG=$'warn-dirty = false\nextra-access-tokens = github.com=fixture_token'
  export GITHUB_TOKEN_CMD='printf "%s\n" fixture_token'
  if ! output=$(just update 2>&1); then
    printf 'Expected authenticated update to pass the token only through NIX_CONFIG\n' >&2
    return 1
  fi
  [[ $output == *'fake Nix reached'* && $output != *fixture_token* ]]
  # The common inherited xtrace setting must not reveal command output or assignments.
  output=$(env SHELLOPTS=xtrace just update 2>&1)
  [[ $output == *'fake Nix reached'* && $output != *fixture_token* ]]
  export EXPECT_NIX_CONFIG="$NIX_CONFIG"
  output=$(env -u GITHUB_TOKEN_CMD just update 2>&1)
  [[ $output == *'fake Nix reached'* ]]
  export EXPECT_INPUT=disko GITHUB_TOKEN_CMD='exit 42'
  output=$(just update-input disko 2>&1)
  [[ $output == *'fake Nix reached'* ]]
  local broken
  for broken in 'printf redacted_fixture >&2; exit 1' 'true' 'printf "fixture_token\ninjected = true\n"'; do
    if output=$(GITHUB_TOKEN_CMD="$broken" just update 2>&1); then
      printf 'Expected invalid GitHub token helper to stop the update\n' >&2
      return 1
    fi
    [[ $output == *GITHUB_TOKEN_CMD* && $output != *'fake Nix reached'* ]]
    [[ $output != *redacted_fixture* && $output != *fixture_token* ]]
  done
)
check_update_auth

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
