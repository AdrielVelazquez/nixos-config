final: prev:

{
  asdbctl = prev.asdbctl.overrideAttrs (_old: {
    version = "1.1.0";

    src = prev.fetchFromGitHub {
      owner = "juliuszint";
      repo = "asdbctl";
      tag = "v1.1.0";
      hash = "sha256-jDflaksnsw55RHMgamfJNRE7GwThQMYfXtLAWbOnoMw=";
    };

    cargoHash = "sha256-OPmnGh6xN6XeREeIgyYB2aeHUpdQ5hFS5MivcTeY29E=";
  });
}
