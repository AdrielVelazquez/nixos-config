{
  writeShellApplication,
  go,
  git,
  openssh,
  cloudflared,
}:

writeShellApplication {
  name = "llmp";
  derivationArgs = {
    pname = "llmp";
    version = "0.2.2";
  };
  runtimeInputs = [
    go
    git
    openssh
    cloudflared
  ];
  text = ''
    # Fetch private modules as the invoking user, using their Git/SSH credentials.
    # Neither source downloads nor credentials are part of the Nix build.
    export GOPRIVATE="''${GOPRIVATE:+$GOPRIVATE,}github.snooguts.net"
    export GOTOOLCHAIN=local
    export CGO_ENABLED=0

    # llmp/v0.2.2; see TODO.md for the upstream packaging/removal criteria.
    exec go run github.snooguts.net/reddit/llm-platform/cmd/llmp@6f51373127d8b7f4966dd28c7778261c239119a4 "$@"
  '';
}
