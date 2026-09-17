{ callPackage }:

# Headroom 0.37.0 requires the pre-1.0 language-pack API. Reuse the upstream
# 0.13.0 package recipe with this flake's current Python package set.
callPackage (builtins.fetchurl {
  url = "https://raw.githubusercontent.com/NixOS/nixpkgs/cc53eadbdb10015c09c2bd48c6e82877b2f777ee/pkgs/development/python-modules/tree-sitter-language-pack/default.nix";
  sha256 = "sha256-jMPioaOCypGY0t8DWIg4MiB3NQikw0A6kAFjvhwrsoQ=";
}) { }
