{ stdenvNoCC, fetchzip }:

stdenvNoCC.mkDerivation {
  pname = "opencode-llm-platform-v2";
  version = "0.4.1";

  src = fetchzip {
    name = "opencode-llm-platform-v2-0.4.1";
    url = "https://artifactory.build.ue1.snooguts.net/artifactory/api/npm/reddit-npm-prod/@reddit/opencode-llm-platform-v2/-/opencode-llm-platform-v2-0.4.1.tgz";
    hash = "sha256-HC/aAKeFgBV+LgDca3+vQ5qHLSx4/Lln6LNd2dPRfAA=";
  };

  # Upstream 0.4.2 still requests first-party-only LLMP scopes with a dynamic
  # client. Correct the shared fresh/cached metadata reader, not server policy.
  # Explicit operator scopes remain untouched. See TODO.md for removal gates.
  postPatch = ''
    substituteInPlace src/tools-oauth.mjs \
      --replace-fail 'return [...new Set(scopes)].join(" ")' \
        'const allowedScopes = scopes.filter((scope) => !scope.startsWith("tool:llmp:"))
      if (allowedScopes.length === 0) throw new Error("Tool Registry OAuth metadata has no eligible scopes")
      return [...new Set(allowedScopes)].join(" ")'
  '';

  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -R . "$out/"
    runHook postInstall
  '';
}
