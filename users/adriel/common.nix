# users/adriel/common.nix
#
# Shared HM config for the personal `adriel` user across hosts.
# Anything host-specific (e.g. razer14's niri DRM device paths) belongs in
# the per-host wrapper (users/adriel/default.nix, users/adriel-dell/default.nix, ...).
{ pkgs, ... }:

{
  imports = [
    ./linux-baseline.nix
  ];

  local.git = {
    userEmail = "AdrielVelazquez@gmail.com";
    extraInsteadOf = {
      "git@github.com:" = {
        pushInsteadOf = "https://github.com/";
      };
    };
  };

  home.sessionVariables = {
    BROWSER = "zen-browser";
    TERMINAL = "kitty";
  };

  home.packages = with pkgs; [
    discord
    # bottles
    popsicle
    pince
    scanmem
    (llama-cpp.override { cudaSupport = true; })
  ];

  services.gnome-keyring.enable = true;
}
