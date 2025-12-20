# dev-shells/python.nix
# Python development shell with common packages
{ pkgs }:

pkgs.mkShell {
  packages = [
    (pkgs.python3.withPackages (python-pkgs: [
      python-pkgs.pandas
      python-pkgs.requests
    ]))
  ];

  shellHook = ''
    echo "Python development shell activated"
    python --version
  '';
}
