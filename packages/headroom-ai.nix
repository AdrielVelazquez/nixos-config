{
  lib,
  callPackage,
  patch,
  stdenv,
  fetchPypi,
  autoPatchelfHook,
  ast-grep,
  difftastic,
  scc,
  python3Packages,
}:

let
  coreDependencies = with python3Packages; [
    click
    opentelemetry-api
    pydantic
    pyyaml
    rich
    tiktoken
    tomlkit
  ];

  proxyDependencies = with python3Packages; [
    fastapi
    h2
    httpx
    magika
    mcp
    onnxruntime
    openai
    orjson
    sqlite-vec
    transformers
    uvicorn
    watchdog
    websockets
    zstandard
  ];
in
python3Packages.buildPythonApplication rec {
  pname = "headroom-ai";
  version = "0.37.0";
  format = "wheel";

  src = fetchPypi {
    pname = "headroom_ai";
    inherit version;
    format = "wheel";
    dist = "cp310";
    python = "cp310";
    abi = "abi3";
    platform = "manylinux_2_28_x86_64";
    hash = "sha256-Lvxc32gaEMX8eionGkcRecQJB0U3BF9oKxDk1ySXb0Y=";
  };

  nativeBuildInputs = [
    python3Packages.pythonRelaxDepsHook
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  pythonRemoveDeps = [ "ast-grep-cli" ];

  dependencies = coreDependencies ++ proxyDependencies;

  pythonImportsCheck = [
    "headroom"
    "headroom._core"
  ];

  postInstall = ''
    ${patch}/bin/patch \
      --directory "$out/${python3Packages.python.sitePackages}" \
      --strip 1 \
      < ${callPackage ./headroom-ai-path-idempotent-memory-mcp.nix { }}
    ${patch}/bin/patch \
      --directory "$out/${python3Packages.python.sitePackages}" \
      --strip 1 \
      < ${callPackage ./headroom-ai-path-configurable-codex-ws-timeout.nix { }}
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    PYTHONPATH="$out/${python3Packages.python.sitePackages}:$PYTHONPATH" \
      ${python3Packages.python.interpreter} ${./tests/headroom-codex-ws-timeout.py} -v
    runHook postInstallCheck
  '';

  makeWrapperArgs = [
    "--prefix"
    "PYTHONPATH"
    ":"
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
    description = "Context compression CLI for AI agents";
    homepage = "https://github.com/headroomlabs-ai/headroom";
    license = lib.licenses.asl20;
    mainProgram = "headroom";
    platforms = [ "x86_64-linux" ];
  };
}
