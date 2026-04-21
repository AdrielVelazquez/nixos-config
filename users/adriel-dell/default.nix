# users/adriel-dell/default.nix
#
# Personal `adriel` user on the dell-plex-server box. Same shared base as
# the razer14 user, minus the razer14-specific niri/dGPU config.
#
# TODO: dell currently runs GNOME at the system level. If/when niri gets
# wired up here, set `local.niri = { enable = true; renderDevice = ...; };`
# with the dell DRM paths (use `ls -l /dev/dri/by-path/`).
{ ... }:

{
  imports = [
    ../adriel/common.nix
  ];
}
