{
  lib,
  stdenv,
  fetchPypi,
  autoPatchelfHook,
  ast-grep,
  difftastic,
  scc,
  python3Packages,
}:

let
  headroomLanguagePack =
    python3Packages.callPackage ./tree-sitter-language-pack-path-headroom-compat.nix
      { };

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

  compressionDependencies = with python3Packages; [
    fastembed
    trafilatura
    tree-sitter
    headroomLanguagePack
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

  dependencies = coreDependencies ++ proxyDependencies ++ compressionDependencies;

  pythonImportsCheck = [
    "headroom"
    "headroom._core"
    "fastembed"
    "trafilatura"
    "tree_sitter"
    "tree_sitter_language_pack"
  ];

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    HEADROOM_TOOL_DESC_MAX_CHARS=1024 \
      HEADROOM_TOOL_DESC_STRIP_SEMANTIC=0 \
      HF_HUB_OFFLINE=1 \
      TRANSFORMERS_OFFLINE=1 \
      PYTHONPATH="$out/${python3Packages.python.sitePackages}:$PYTHONPATH" \
      ${python3Packages.python.interpreter} ${./tests/headroom-compression-extras.py} -v
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
