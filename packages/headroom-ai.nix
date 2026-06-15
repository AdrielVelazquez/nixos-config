{
  lib,
  fetchurl,
  python3Packages,
  autoPatchelfHook,
  ast-grep,
  stdenv,
}:

python3Packages.buildPythonApplication rec {
  pname = "headroom-ai";
  version = "0.25.0";
  format = "wheel";

  src = fetchurl {
    url = "https://github.com/chopratejas/headroom/releases/download/v${version}/headroom_ai-${version}-cp310-abi3-manylinux_2_28_x86_64.whl";
    hash = "sha256-ICrjH5N+iZMzlEGzY6Lkfrv0NQLiKkR7LGQ9OQhW9Nw=";
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
    rich
    sqlite-vec
    tiktoken
    transformers
    uvicorn
    watchdog
    websockets
    zstandard
  ];

  pythonImportsCheck = [ "headroom" ];

  makeWrapperArgs = [
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath [ ast-grep ])
  ];

  meta = {
    description = "Context compression layer for AI agents";
    homepage = "https://github.com/chopratejas/headroom";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "headroom";
  };
}
