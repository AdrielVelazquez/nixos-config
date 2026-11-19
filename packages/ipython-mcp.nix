# ipython-mcp: ConorForgie/ipython-mcp at commit 8dddf71126c8a09238eb5ab6deef46454cf09643 (MIT, untagged, pyproject
# version 0.1.0). Built from source with nixpkgs' Python dependencies. The server needs mcp 1.x (the same SDK change as
# packages/mcp-dap.nix), and ipykernel must be importable by the interpreter it runs under, since sessions start kernels there.
{
  lib,
  fetchFromGitHub,
  python3Packages,
}:

let
  runtimeDeps = with python3Packages; [
    mcp_1
    jupyter-client
    pyzmq
    ipykernel
  ];
in

python3Packages.buildPythonApplication {
  pname = "ipython-mcp";
  version = "0.1.0-unstable-2026-11-16";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "ConorForgie";
    repo = "ipython-mcp";
    rev = "8dddf71126c8a09238eb5ab6deef46454cf09643";
    hash = "sha256-4pVZPZx7AwUr5iDlSqY5YzWoJHnSZlU+R9MafWf4gsU=";
  };

  build-system = [ python3Packages.hatchling ];

  dependencies = runtimeDeps;

  # Sessions start kernels in a child interpreter (sys.executable), which does not inherit the site-packages the
  # wrapper adds in-process, so the Python path of the dependency closure is exported for it.
  makeWrapperArgs = [
    "--prefix"
    "PYTHONPATH"
    ":"
    (python3Packages.makePythonPath runtimeDeps)
  ];

  doCheck = false;

  meta = {
    description = "MCP server giving Claude a stateful IPython kernel per session, with per-env isolation";
    homepage = "https://github.com/ConorForgie/ipython-mcp";
    license = lib.licenses.mit;
    mainProgram = "ipython-mcp";
  };
}
