{
  lib,
  stdenv,
  fetchPypi,
  fetchFromGitHub,
  autoPatchelfHook,
  ast-grep,
  difftastic,
  scc,
  python3Packages,
}:

let
  pythonPackages = python3Packages.overrideScope (
    import ./headroom-path-python-dependencies.nix {
      inherit fetchFromGitHub;
      basePythonPackages = python3Packages;
    }
  );
  headroomLanguagePack =
    pythonPackages.callPackage ./tree-sitter-language-pack-path-headroom-compat.nix
      { };

  coreDependencies = with pythonPackages; [
    click
    filelock
    hf-xet
    litellm
    opentelemetry-api
    pydantic
    pyyaml
    rich
    tiktoken
    tomlkit
    truststore
  ];

  proxyDependencies = with pythonPackages; [
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

  compressionDependencies = with pythonPackages; [
    fastembed
    trafilatura
    tree-sitter
    headroomLanguagePack
  ];
in
pythonPackages.buildPythonApplication rec {
  pname = "headroom-ai";
  version = "0.42.0";
  format = "wheel";

  env = {
    HEADROOM_OFFLINE = "1";
    LITELLM_LOCAL_MODEL_COST_MAP = "True";
  };

  src = fetchPypi {
    pname = "headroom_ai";
    inherit version;
    format = "wheel";
    dist = "cp310";
    python = "cp310";
    abi = "abi3";
    platform = "manylinux_2_28_x86_64";
    hash = "sha256-+7POuPbD8gjtzDqtQ8DgPg20VjbZ0gYVJa0NChZtoUY=";
  };

  nativeBuildInputs = [
    pythonPackages.pythonRelaxDepsHook
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  pythonRemoveDeps = [ "ast-grep-cli" ];

  dependencies = coreDependencies ++ proxyDependencies ++ compressionDependencies;

  pythonImportsCheck = [
    "headroom"
    "headroom._core"
    "filelock"
    "litellm"
    "mcp.server.lowlevel"
    "fastembed"
    "trafilatura"
    "tree_sitter"
    "tree_sitter_language_pack"
  ];

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    for test in ${./tests/headroom-compression-extras.py} ${./tests/headroom-output-shaping.py}; do
      HEADROOM_TOOL_DESC_MAX_CHARS=1024 \
        HEADROOM_TOOL_DESC_STRIP_SEMANTIC=0 \
        HF_HUB_OFFLINE=1 \
        TRANSFORMERS_OFFLINE=1 \
        PYTHONPATH="$out/${pythonPackages.python.sitePackages}:$PYTHONPATH" \
        ${pythonPackages.python.interpreter} "$test" -v
    done
    runHook postInstallCheck
  '';

  makeWrapperArgs = [
    "--prefix"
    "PYTHONPATH"
    ":"
    (
      "${placeholder "out"}/${pythonPackages.python.sitePackages}:"
      + pythonPackages.makePythonPath (pythonPackages.requiredPythonModules dependencies)
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
