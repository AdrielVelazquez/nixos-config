# users/adriel/default.nix
#
# Personal `adriel` user, razer14 flavor. Adds niri config tied to the
# razer14 hybrid GPU layout. The reusable bits live in ./common.nix.
{ pkgs, lib, ... }:

let
  # sops-nix fails to install every secret when a declared key is missing from the file, so Pi's
  # OpenCode key is wired only once it exists there.
  hasOpencodeKey = lib.any (line: lib.hasPrefix "opencodego_api_key:" line) (
    lib.splitString "\n" (builtins.readFile ../../secrets/secrets-enc.yaml)
  );

  llamaCpp = pkgs.llama-cpp.override { cudaSupport = true; };

  # Serves the model that dotfiles/opencode/opencode.json's `llama-cpp` provider
  # expects on 127.0.0.1:8080. GPU layer and MoE expert placement are left unset
  # so llama-server's default --fit sizes them to the free VRAM; set
  # LLAMA_N_CPU_MOE (or pass --n-gpu-layers) to take over. Extra arguments pass
  # through to llama-server.
  llamaServe = pkgs.writeShellApplication {
    name = "llama-serve";
    runtimeInputs = [ llamaCpp ];
    text = ''
      model="''${LLAMA_MODEL:-HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive:Q4_K_M}"
      placement=()
      if [ -n "''${LLAMA_N_CPU_MOE:-}" ]; then
        placement=(--n-gpu-layers 99 --n-cpu-moe "$LLAMA_N_CPU_MOE")
      fi
      exec llama-server \
        --hf-repo "$model" \
        --alias "$model" \
        --host 127.0.0.1 \
        --port "''${LLAMA_PORT:-8080}" \
        --ctx-size "''${LLAMA_CTX:-124000}" \
        --jinja \
        --chat-template-file ${../../llama-templates/qwen3-opencode.jinja} \
        --flash-attn on \
        "''${placement[@]}" \
        "$@"
    '';
  };
in
{
  imports = [
    ./common.nix
    ../../modules/home-manager/opencode-go.nix
    ../../modules/home-manager/opencode-work.nix
  ];

  local.niri = {
    enable = true;
    appleStudioDisplay.enable = true;
    renderDevice = "/dev/dri/by-path/pci-0000:c5:00.0-render";
    ignoreDrmDevice = "/dev/dri/by-path/pci-0000:c4:00.0-card";
    brightnessDevice = "amdgpu_bl1";
    dgpuPciPath = "/sys/bus/pci/devices/0000:c4:00.0";
    services.internalDisplayAutoOff = {
      enable = true;
      output = "eDP-1";
      ignoredOutputDescriptions = [ "Unknown Unknown Unknown" ];
    };
  };
  home.packages = [
    llamaCpp
    llamaServe
  ];
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
  local.noctalia.enable = false;
  local.sops.ageKeyFile = "/home/adriel/.config/sops/age/keys.txt";

  local.opencode = {
    go = {
      enable = true;
      # Cheap default session model; the per-agent routing below keeps the
      # stronger build and plan models.
      defaultModel = "opencode-go/glm-5.3-flash";
    };
    routing.agents = {
      # Compaction stays unrouted so it can reuse the session's warm prompt cache.
      plan = "opencode-go/mimo-v2.6-pro";
      build = "opencode-go/claude-haiku-5-5#high";
      scout = "opencode-go/glm-5.3-flash#low";
      explore = "opencode/deepseek-v4.1-flash-free#low";
      title = "opencode/deepseek-v4.1-flash-free#low";
    };
  };

  # Pi uses OpenCode Go only. Its sign-in comes from the SOPS secret `opencodego_api_key` (see local.pi.apiKeys
  # below); `/login` still works as a fallback. OpenCode Zen is not configured: its free models are refused for
  # any client but OpenCode ("free tier can only be used from within opencode"), and Go's own `-free` models are
  # left out for the same reason. GLM-5.3 and GLM-5.3-Flash accept only low/high/max; Kimi K2.7 Code and
  # MiMo V2.6 Flash have no thinking variants, so they run with thinking off. The `pi-razer` check verifies
  # every selector against Pi's catalog.
  local.pi.modelRoles = {
    enable = true;
    roles = {
      default = "opencode-go/kimi-k2.7-code:off";
      plan = "opencode-go/glm-5.3:high";
      slow = "opencode-go/glm-5.3:max";
      smol = "opencode-go/glm-5.3-flash:low";
      commit = "@smol";
      widget = "@smol";
      tiny = "opencode-go/mimo-v2.6-flash:off";
      memory = "@tiny";
      task = "opencode-go/kimi-k2.7-code:off";
      # A second model family from the default gives /advisor an independent review.
      advisor = "opencode-go/glm-5.3:high";
      # GLM-5.3 is text-only; Kimi accepts images.
      vision = "opencode-go/kimi-k2.7-code:off";
    };
    taskAgents = {
      build = "opencode-go/kimi-k2.7-code:off";
      scout = "opencode-go/glm-5.3-flash:low";
      explore = "opencode-go/mimo-v2.6-flash:off";
    };
    # Go limits are a dollar cap per model, and GLM-5.3 has the smallest, so each role has a model with its
    # own cap to move to. Pi falls back on rate limits, quota, overload and context overflow, never on
    # authentication errors, and agents (build, scout, explore, title) are fixed and never fall back.
    modelFallback = true;
    fallbackChains =
      let
        glm52 = "opencode-go/glm-5.2";
        flash = [ "opencode-go/glm-5.3-flash:low" ];
        mimo = [ "opencode-go/mimo-v2.6-flash:off" ];
      in
      {
        default = [ "${glm52}:high" ];
        plan = [ "${glm52}:high" ];
        slow = [ "${glm52}:max" ];
        advisor = [ "${glm52}:high" ];
        smol = mimo;
        commit = mimo;
        widget = mimo;
        tiny = flash;
        memory = flash;
        # GLM-5.3-Flash takes images; GLM-5.2 does not.
        vision = flash;
      };
  };
  # Headroom routes this built-in provider through the session's proxy.
  local.headroom.pi.providers = {
    opencode-go = "https://opencode.ai/inference/go/v1";
  };
  local.pi.apiKeys = lib.optionalAttrs hasOpencodeKey {
    opencode-go = "opencodego_api_key";
  };

  local.zen-browser = {
    aggressiveGpuAcceleration = true;
    forceIntegratedGpu = true;
  };
}
