{ stdenvNoCC, fetchzip }:

stdenvNoCC.mkDerivation {
  pname = "opencode-llm-platform-v2";
  version = "0.4.3";

  src = fetchzip {
    name = "opencode-llm-platform-v2-0.4.3";
    url = "https://artifactory.build.ue1.snooguts.net/artifactory/api/npm/reddit-npm-prod/@reddit/opencode-llm-platform-v2/-/opencode-llm-platform-v2-0.4.3.tgz";
    hash = "sha256-FbSA7pNum0/As7IW7ibeE0UbHIClt15lwIzhpcYfUxI=";
  };

  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -R . "$out/"
    runHook postInstall
  '';
}
