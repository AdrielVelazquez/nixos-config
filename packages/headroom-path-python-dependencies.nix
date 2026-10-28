{ fetchFromGitHub, basePythonPackages }:
final: prev: {
  # Keep build/test harnesses on the primary set, not the runtime overrides.
  inherit (basePythonPackages) mypy pytest-xdist torch;

  # The primary binary meets Headroom's floor without overridden runtime dependencies.
  inherit (basePythonPackages) onnxruntime;

  filelock = final.callPackage (builtins.fetchurl {
    url = "https://raw.githubusercontent.com/NixOS/nixpkgs/145ee526b4a1cc4a633bbd898f3a7c08989d2c89/pkgs/development/python-modules/filelock/default.nix";
    sha256 = "sha256-+va3yc6b12iWwm24PrN5aRy5B8L59cLdRYVQ2vvhSXs=";
  }) { };

  litellm = final.callPackage (builtins.fetchurl {
    url = "https://raw.githubusercontent.com/NixOS/nixpkgs/02c087f3fe673c9e317f206a627cb6b910336dbe/pkgs/development/python-modules/litellm/default.nix";
    sha256 = "0pfzqwfqllnr2prv5p3ycffrdi1xk16b4fklx456wdmwwln6fncj";
  }) { };

  python-discovery = final.callPackage (builtins.fetchurl {
    url = "https://raw.githubusercontent.com/NixOS/nixpkgs/15b831341bcb82abf9a1fc88eab2d7744f1b2f9b/pkgs/development/python-modules/python-discovery/default.nix";
    sha256 = "sha256-w7vo/PemotoxQGcoVEA1nuRR//7RtrC5F9UYCEI7OD8=";
  }) { };

  virtualenv = final.callPackage (builtins.fetchurl {
    url = "https://raw.githubusercontent.com/NixOS/nixpkgs/15b831341bcb82abf9a1fc88eab2d7744f1b2f9b/pkgs/development/python-modules/virtualenv/default.nix";
    sha256 = "sha256-MVOWdX2YJBMW7ncFDkVPTiNUAY7y7rRWkj98gVRsR1I=";
  }) { };

  mcp = prev.mcp_1.overridePythonAttrs {
    version = "1.30.0";
    src = fetchFromGitHub {
      owner = "modelcontextprotocol";
      repo = "python-sdk";
      tag = "v1.30.0";
      hash = "sha256-EkmTqsK+vBJcURuwFkhtNJMFgtzgw/7Cd+Fpav4P/ko=";
    };
  };
}
