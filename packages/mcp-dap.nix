# MCP DAP bridge: ztripez/mcp-dap at commit 9d6c84414320a34a273e047aaaa32e4c510253ed (MIT, version 0.1.0, untagged).
# Built from source with nixpkgs' Python dependencies. debugpy comes from nixpkgs, so the Python adapter runs from the
# same interpreter. The code targets the mcp 1.x API (Server.list_tools), so mcp_1 replaces nixpkgs' mcp 2.x, which removed it.
{
  lib,
  fetchFromGitHub,
  python3Packages,
}:

python3Packages.buildPythonApplication {
  pname = "mcp-dap";
  version = "0.1.0-unstable-2026-11-16";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "ztripez";
    repo = "mcp-dap";
    rev = "9d6c84414320a34a273e047aaaa32e4c510253ed";
    hash = "sha256-pAvrd5cF3aNF2mR3IajQgBB7xg92C1sCCbO1OS1B+W8=";
  };

  build-system = [ python3Packages.hatchling ];

  dependencies = with python3Packages; [
    mcp_1
    pydantic
    anyio
    debugpy
    pydantic-settings
  ];

  # The debugpy adapter starts as a child process (sys.executable -m debugpy.adapter), which does not inherit the
  # site-packages the wrapper adds in-process, so PYTHONPATH carries debugpy to it.
  makeWrapperArgs = [
    "--prefix"
    "PYTHONPATH"
    ":"
    "${python3Packages.debugpy}/${python3Packages.python.sitePackages}"
  ];

  doCheck = false;

  meta = {
    description = "MCP-DAP bridge for enabling code agents to debug processes via Debug Adapter Protocol";
    homepage = "https://github.com/ztripez/mcp-dap";
    license = lib.licenses.mit;
    mainProgram = "mcp-dap";
  };
}
