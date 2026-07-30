# users/adriel-cachyos/default.nix
# CachyOS Framework 13 user config (work laptop)
{ pkgs, ... }:

{
  imports = [
    ../adriel/linux-baseline.nix
    ../../modules/home-manager/opencode-work.nix
  ];

  programs.niri.enable = true;
  local.niri = {
    enable = true;
    appleStudioDisplay.enable = true;
    useSystemHyprlock = true;
    hyprlock.suspendTimeoutSeconds = 1200;
    services.internalDisplayAutoOff = {
      enable = true;
      output = "eDP-1";
      ignoredOutputDescriptions = [ "Unknown Unknown Unknown" ];
    };
  };
  programs.niri.settings.outputs = {
    "eDP-1".scale = 1.1;
    "Apple Computer Inc StudioDisplay 0x92E55162".scale = 1.0;
    "LG Electronics LG HDR 4K 0x00017E3D".scale = 1.0;
    "LG Electronics LG HDR 4K 0x0002C15B".scale = 1.0;
    "DP-8".enable = false;
    "Unknown Unknown Unknown".enable = false;
  };
  local.zoom.enable = true;
  local.sops.ageKeyFile = "/home/adriel/.config/sops/age/keys.txt";

  # Shell & Terminal
  local.kitty.enableGpuRecovery = true;
  local.opencode = {
    llmPlatform = {
      enable = true;
      defaultModel = "llmplatform/claude-opus-4-8";
    };
  };

  # Editor
  local.nixpkgs-review.enable = true;

  # Security & Secrets
  local.ssh = {
    additionalHosts =
      let
        sshca = {
          hostname = "sshca.orch.ue1.snooguts.net";
          user = null;
          identityFile = null;
          forwardAgent = true;
          strictHostKeyChecking = "yes";
        };
      in
      {
        inherit sshca;
        "sshca.orch.ue1.snooguts.net" = sshca;
      };
  };
  local.snoocert.enable = true;

  home.sessionVariables = {
    GOPRIVATE = "github.snooguts.net";
  };

  home.packages = with pkgs; [
    openssl
    ed
    ollama
    slack
    # bottles
    wl-screenrec
    qalculate-qt
    infrared
    snoologin
    reddit-lint-py
    tilt
    cloudflared
    google-cloud-sdk
    tfenv
    brave
    apparmor-utils
    krew
    snoodev-system
    peek
    steam
    thunderbird
  ];

  programs.gh-dash.enable = true;
  programs.obs-studio = {
    enable = true;

    plugins = with pkgs.obs-studio-plugins; [
      wlrobs
      obs-backgroundremoval
      obs-pipewire-audio-capture
      obs-vaapi
      obs-gstreamer
      obs-vkcapture
    ];
  };
}
