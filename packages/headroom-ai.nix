{
  lib,
  fetchurl,
  python3Packages,
  autoPatchelfHook,
  ast-grep,
  difftastic,
  scc,
  stdenv,
}:

python3Packages.buildPythonApplication rec {
  pname = "headroom-ai";
  version = "0.31.0";
  format = "wheel";

  src = fetchurl {
    url = "https://github.com/chopratejas/headroom/releases/download/v${version}/headroom_ai-${version}-cp310-abi3-manylinux_2_28_x86_64.whl";
    hash = "sha256-+qH79lowiVUhmXW3nX0WKfWAzkYniscLamjpcysqa3Y=";
  };

  nativeBuildInputs = [
    python3Packages.pythonRelaxDepsHook
  ]
  ++ lib.optionals stdenv.isLinux [ autoPatchelfHook ];

  pythonRelaxDeps = [ "litellm" ];
  pythonRemoveDeps = [ "ast-grep-cli" ];

  dependencies = with python3Packages; [
    click
    fastapi
    h2
    httpx
    litellm
    magika
    mcp
    onnxruntime
    openai
    opentelemetry-api
    pydantic
    python-socks
    rich
    sqlite-vec
    tiktoken
    tree-sitter-language-pack
    transformers
    uvicorn
    watchdog
    websockets
    zstandard
  ];

  pythonImportsCheck = [ "headroom" ];

  makeWrapperArgs = [
    "--prefix"
    "PYTHONPATH"
    ":"
    # Headroom wrap starts the proxy with `sys.executable -m headroom.cli`.
    # Export the package path so that subprocess can import Headroom too.
    (
      "${placeholder "out"}/${python3Packages.python.sitePackages}:"
      + python3Packages.makePythonPath (python3Packages.requiredPythonModules dependencies)
    )
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath [
      ast-grep
      difftastic
      scc
    ])
  ];

  meta = {
    description = "Context compression layer for AI agents";
    homepage = "https://github.com/chopratejas/headroom";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "headroom";
  };
}
