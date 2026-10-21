# users/adriel/default.nix
#
# Personal `adriel` user, razer14 flavor. Adds niri config tied to the
# razer14 hybrid GPU layout. The reusable bits live in ./common.nix.
{ pkgs, ... }:

let
  llamaCpp = pkgs.llama-cpp.override { cudaSupport = true; };

  # Serves the model that dotfiles/opencode/opencode.json's `llama-cpp` provider
  # expects on 127.0.0.1:8080. Defaults suit the 8 GB dGPU: dense layers on the
  # GPU, all MoE expert weights on the CPU. Lower LLAMA_N_CPU_MOE to move more
  # experts onto the GPU until VRAM is nearly full; extra arguments pass through
  # to llama-server.
  llamaServe = pkgs.writeShellApplication {
    name = "llama-serve";
    runtimeInputs = [ llamaCpp ];
    text = ''
      model="''${LLAMA_MODEL:-HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive:Q4_K_M}"
      exec llama-server \
        --hf-repo "$model" \
        --alias "$model" \
        --host 127.0.0.1 \
        --port "''${LLAMA_PORT:-8080}" \
        --jinja \
        --chat-template-file ${../../llama-templates/qwen3-opencode.jinja} \
        --n-gpu-layers 99 \
        --n-cpu-moe "''${LLAMA_N_CPU_MOE:-99}" \
        --ctx-size "''${LLAMA_CTX:-32768}" \
        --flash-attn on \
        "$@"
    '';
  };
in
{
  imports = [
    ./common.nix
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

  local.zen-browser = {
    aggressiveGpuAcceleration = true;
    forceIntegratedGpu = true;
  };
}
