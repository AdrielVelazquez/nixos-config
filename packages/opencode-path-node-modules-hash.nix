{
  stdenv,
  opencode,
}:

# Original issue: nixos-unstable (1d060086d60cb76a40cf37109f979d88a5bd6396) ships
# opencode 2.2.5 with node_modules outputHash sha256-xfOV…, but the Linux build
# produces sha256-prx9…. nixpkgs master (package.nix) already carries the
# corrected platform-split hashes; this file copies only those values.
# Remove once nixos-unstable's opencode package.nix has the same hashes.
opencode.overrideAttrs (old: {
  node_modules = old.node_modules.overrideAttrs {
    outputHash =
      if stdenv.hostPlatform.isLinux then
        "sha256-prx9dX7kUvs/E3zopkaPk5LXh3xJAy5sZeum/W8L7cA="
      else if stdenv.hostPlatform.isDarwin then
        "sha256-dIveiaiPFGSItwLyeMuPDxTE9gpvvnlTCB/+nG24qCc="
      else
        throw "Unsupported platform";
  };
})
