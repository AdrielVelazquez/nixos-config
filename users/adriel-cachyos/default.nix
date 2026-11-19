{ pkgs, ... }:

{
  imports = [ ../adriel-work ];
  home.packages = [ pkgs.codex ];

  local.niri.useSystemHyprlock = true;
}
