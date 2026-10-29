# users/adriel-cachyos/default.nix
# CachyOS Framework 13 user config (work laptop)
{
  config,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    ../adriel/linux-baseline.nix
    ../../modules/home-manager/opencode-work.nix
  ];

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
  wayland.windowManager.niri.settings._children = [
    {
      output = {
        _args = [ "Apple Computer Inc StudioDisplay 0x92E55162" ];
        scale = 1.5;
        transform = "normal";
      };
    }
    {
      output = {
        _args = [ "DP-8" ];
        off = { };
        transform = "normal";
      };
    }
    {
      output = {
        _args = [ "LG Electronics LG HDR 4K 0x00017E3D" ];
        scale = 1.0;
        transform = "normal";
      };
    }
    {
      output = {
        _args = [ "LG Electronics LG HDR 4K 0x0002C15B" ];
        scale = 1.0;
        transform = "normal";
      };
    }
    {
      output = {
        _args = [ "Unknown Unknown Unknown" ];
        off = { };
        transform = "normal";
      };
    }
    {
      output = {
        _args = [ "eDP-1" ];
        scale = 1.1;
        transform = "normal";
      };
    }
  ];
  local.zoom.enable = true;
  local.sops.ageKeyFile = "/home/adriel/.config/sops/age/keys.txt";

  # Shell & Terminal
  local.kitty.enableGpuRecovery = true;
  local.opencode = {
    enable = true;
    # Preserve the remaining live CLI preferences when restoring declarative files.
    cliSettings = {
      diffs.wrap = "word";
      session = {
        sidebar = "auto";
        scrollbar = false;
        thinking = "show";
      };
      animations = true;
    };
    llmPlatform = {
      enable = true;
      # Pi already installs the same shared llmp CLI; don't duplicate its package.
      cli.enable = false;
      defaultModel = "llmplatform/gpt-6.1-sol";
    };
    routing = {
      enable = true;
      agents = {
        plan = "llmplatform/claude-sonnet-5-5#xhigh";
        build = "llmplatform/gpt-6.1-sol#high";
        scout = "llmplatform/gpt-6.1-sol#low";
        explore = "llmplatform/gpt-6-luna#low";
        title = "llmplatform/gpt-6-luna#low";
      };
    };
  };
  local.openspec.enable = true;
  # The standalone Pi features and the shared Pi settings come from ../adriel/pi-baseline.nix; only
  # LLM Platform and the role models are Framework-specific.
  local.headroom.pi.providers.llm-platform.enable = true;
  local.pi = {
    ui = {
      theme = "cyberdream";
      terminalThemes.enable = false;
    };
    llmPlatform = {
      enable = true;
      package = inputs.pi-reddit-provider.outPath;
      cli.enable = true;
      defaultModel = "gpt-6.1-sol";
    };
    modelRoles.roles = {
      default = "llm-platform/claude-haiku-5-5:medium";
      plan = "llm-platform/claude-sonnet-5-5:high";
      slow = "llm-platform/claude-sonnet-5-5:xhigh";
      smol = "llm-platform/gpt-6-luna:low";
      commit = "@smol";
      widget = "@smol";
      tiny = "llm-platform/gpt-6-luna:low";
      memory = "@tiny";
      task = "llm-platform/gpt-6.1-sol:medium";
      # A second model family gives /advisor an independent review.
      advisor = "llm-platform/gpt-6.1-sol:high";
      vision = "llm-platform/gpt-6.1-sol:high";
    };
    modelRoles.taskAgents.build = "llm-platform/gpt-6.1-sol:medium";
  };

  # Editor
  local.nixpkgs-review.enable = true;

  # Security & Secrets
  # Match Reddit's SSH CA configuration only on the work laptop.
  programs.ssh.settings."ca sshca sshca.orch.ue1.snooguts.net" = {
    HostName = "sshca.orch.ue1.snooguts.net";
    ForwardAgent = true;
    UserKnownHostsFile = "/dev/null";
    StrictHostKeyChecking = "no";
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
    kdePackages.kdenlive
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
    reco
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
