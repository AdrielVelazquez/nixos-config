# ast-grep MCP server: spiritledsoftware/ast-grep-mcp v0.0.2 (MIT, npm ast-grep-mcp 0.0.2), built from the tagged
# source with its pnpm lockfile. The server finds ast-grep through AST_GREP_BIN, which the consumer module sets to
# nixpkgs' ast-grep, so the bundled @ast-grep/cli binary is never used.
{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpmConfigHook,
  pnpm_11,
  nodejs_24,
  makeWrapper,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "ast-grep-mcp";
  version = "0.0.2";

  src = fetchFromGitHub {
    owner = "spiritledsoftware";
    repo = "ast-grep-mcp";
    rev = "b27e93e7dfa84a7ef0bacc7da9b678e23e1abe6a";
    hash = "sha256-Es94l+W8x+FiaBdclLKqbPjijncooZGNOGWP4touf/o=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_11;
    fetcherVersion = 4;
    hash = "sha256-VjVd8y6qqaY08NHWVOEH3rsqqJNgTLLtNA7+j22NOek=";
  };

  nativeBuildInputs = [
    nodejs_24
    pnpm_11
    pnpmConfigHook
    makeWrapper
  ];

  buildPhase = ''
    runHook preBuild
    pnpm run build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/ast-grep-mcp
    cp -r dist package.json node_modules $out/lib/ast-grep-mcp/
    makeWrapper ${nodejs_24}/bin/node $out/bin/ast-grep-mcp \
      --add-flags $out/lib/ast-grep-mcp/dist/index.js
    runHook postInstall
  '';

  meta = {
    description = "MCP stdio server exposing ast-grep structural search and safe rewrites to agents";
    license = lib.licenses.mit;
    mainProgram = "ast-grep-mcp";
  };
})
