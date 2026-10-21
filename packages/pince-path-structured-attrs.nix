# packages/pince-path-structured-attrs.nix
#
# Temporary local workaround for nixpkgs PR #571813, which made Python packages
# build with `__structuredAttrs = true`. `makeWrapperArgs` is then a real bash
# array, so pince's packed strings such as `--prefix PATH : ...` reach
# makeCWrapper as one argument and the fixup phase fails with
# `makeCWrapper: Unknown argument --chdir "$out/lib/pince"`.
#
# Upstream fix: nixpkgs PR #575801 (open, treewide). Remove this file once it
# reaches nixos-unstable. See TODO.md.
{ pince }:
pince.overrideAttrs { __structuredAttrs = false; }
