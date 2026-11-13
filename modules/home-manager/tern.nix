# modules/home-manager/tern.nix
#
# Tern is closed beta and is not packaged in Nix. The release tarball is
# extracted by hand to `executable`; the path is a plain string, so the binary
# never enters the Nix store.
{
  lib,
  config,
  ...
}:

{
  options.local.tern = {
    enable = lib.mkEnableOption "Tern multiplexing terminal (closed beta, installed outside the Nix store)";
    executable = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.local/opt/tern/tern";
      description = "Absolute path to the manually extracted Tern binary.";
    };
  };
}
