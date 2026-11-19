# OpenCode v2 hashline plugin: npm opencode-v2-hashline 0.1.0 (MIT, https://github.com/Asura7170/opencode-v2-hashline).
# Pinned to the npm tarball's integrity value. The plugin's runtime dependency, @opencode/plugin, comes from OpenCode itself.
{
  fetchurl,
  gnutar,
  gzip,
  runCommand,
}:
let
  tarball = fetchurl {
    url = "https://registry.npmjs.org/opencode-v2-hashline/-/opencode-v2-hashline-0.1.0.tgz";
    hash = "sha512-NUH+bk9geOyCxSiZF63qK/H8/JOr+LYz/lEu/SLq+XbZRaWCf3Hx37tKHAiZLq3FHKBYyE2CwRKgow0mpPxFHQ==";
  };
in
runCommand "opencode-v2-hashline-0.1.0"
  {
    nativeBuildInputs = [
      gnutar
      gzip
    ];
  }
  ''
    mkdir -p $out
    tar -xzf ${tarball} -C $out --strip-components=1
  ''
