{
  lib,
  fetchPypi,
  python3Packages,
}:
python3Packages.buildPythonApplication rec {
  pname = "serena-agent";
  version = "2.1.0";
  format = "wheel";

  src = fetchPypi {
    pname = "serena_agent";
    inherit version;
    format = "wheel";
    dist = "py3";
    python = "py3";
    hash = "sha256-zGrlQsObTeXZjN81pM6wtVHzFsXyLp0PCwxfNda5XYc=";
  };

  nativeBuildInputs = [ python3Packages.pythonRelaxDepsHook ];

  # Serena pins exact versions; nixpkgs carries newer compatible releases.
  pythonRelaxDeps = true;

  dependencies = with python3Packages; [
    anthropic
    beautifulsoup4
    click
    cryptography
    docstring-parser
    filelock
    flask
    jinja2
    joblib
    lsprotocol
    mcp
    oslex
    overrides
    pathspec
    psutil
    pydantic
    pygls
    pystray
    python-dotenv
    python-multipart
    pywebview
    pyyaml
    regex
    requests
    ruamel-yaml
    sensai-utils
    starlette
    tiktoken
    tqdm
    types-pyyaml
    urllib3
    werkzeug
  ];

  pythonImportsCheck = [ "serena" ];

  meta = {
    description = "Coding agent toolkit with semantic code tools (MCP server)";
    homepage = "https://pypi.org/project/serena-agent/";
    license = lib.licenses.mit;
    mainProgram = "serena";
    platforms = lib.platforms.linux;
  };
}
