#!/usr/bin/env bash
# hosts/razer14/run-flux.sh
#
# Run the kpsss34/FHDR_Uncensored FLUX model through stable-diffusion.cpp on
# razer14's NVIDIA dGPU (PRIME offload).
#
# Usage:
#   ./run-flux.sh "your prompt here"
#   PROMPT="..." STEPS=30 HEIGHT=1024 WIDTH=1024 ./run-flux.sh
#
# Env overrides:
#   MODEL_DIR     where weights live / are downloaded to (default: ~/sd-models)
#   OUTPUT        output PNG path                       (default: ./out.png)
#   STEPS         sampler steps                         (default: 20)
#   HEIGHT/WIDTH  image dims                            (default: 1024x1024)
#   CFG_SCALE     classifier-free guidance              (default: 1.0, FLUX-dev)
#   SAMPLER       sampling method                       (default: euler)
#   SEED          rng seed; -1 = random                 (default: -1)
#   T5_QUANT      "fp8" (lighter) or "fp16"             (default: fp8)
#   DIT_QUANT     "Q4_K_M" or "Q8_0"                    (default: Q4_K_M)
#   CLIP_ON_CPU   1 to keep CLIP-L on CPU               (default: 1)
#                 Workaround for sd-cli FPE on FLUX
#                 (https://github.com/leejet/stable-diffusion.cpp/issues/837)
#                 and also saves ~250MB of VRAM.
#   VAE_ON_CPU    1 to keep VAE on CPU                  (default: 0)
#   T5_ON_CPU     1 to keep T5 on CPU                   (default: 1)
#                 4.9GB fp8 T5 would not fit alongside the diffusion model
#                 in 8GB anyway.
#   FLASH_ATTN    1 to use flash attention              (default: 1)
#                 Cuts diffusion compute buffer roughly in half.
#   VAE_TILING    1 to tile VAE decode                  (default: 1)
#   EXTRA_SD_ARGS appended verbatim to the sd invocation

set -euo pipefail

MODEL_DIR="${MODEL_DIR:-$HOME/sd-models}"
OUTPUT="${OUTPUT:-./out.png}"
STEPS="${STEPS:-20}"
HEIGHT="${HEIGHT:-1024}"
WIDTH="${WIDTH:-1024}"
CFG_SCALE="${CFG_SCALE:-1.0}"
SAMPLER="${SAMPLER:-euler}"
SEED="${SEED:--1}"
T5_QUANT="${T5_QUANT:-fp8}"
DIT_QUANT="${DIT_QUANT:-Q4_K_M}"
CLIP_ON_CPU="${CLIP_ON_CPU:-1}"
VAE_ON_CPU="${VAE_ON_CPU:-0}"
T5_ON_CPU="${T5_ON_CPU:-1}"
FLASH_ATTN="${FLASH_ATTN:-1}"
VAE_TILING="${VAE_TILING:-1}"
EXTRA_SD_ARGS="${EXTRA_SD_ARGS:-}"
PROMPT="${1:-${PROMPT:-a portrait of a woman in soft window light, 35mm film grain}}"

case "$T5_QUANT" in
  fp8)  T5_FILE="t5xxl_fp8_e4m3fn.safetensors" ;;
  fp16) T5_FILE="t5xxl_fp16.safetensors" ;;
  *) echo "T5_QUANT must be fp8 or fp16" >&2; exit 2 ;;
esac

case "$DIT_QUANT" in
  Q4_K_M|Q8_0) DIT_FILE="FHDR_ComfyUI-${DIT_QUANT}.gguf" ;;
  *) echo "DIT_QUANT must be Q4_K_M or Q8_0" >&2; exit 2 ;;
esac

FLAKE_DIR="${FLAKE_DIR:-$HOME/.nixos}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing '$1' on PATH; run inside:" >&2
    echo "  nix shell $FLAKE_DIR#stable-diffusion-cpp-cuda nixpkgs#python3Packages.huggingface-hub" >&2
    exit 1
  }
}
need sd-cli
need hf

# Sanity: warn if the sd-cli on PATH was built without CUDA. The CPU build
# crashes loading CLIP-L on some hosts and is far too slow for FLUX anyway.
if ! sd-cli --help 2>&1 | grep -qi cuda \
   && ! ldd "$(command -v sd-cli)" 2>/dev/null | grep -qi cuda; then
  cat >&2 <<EOF
warning: sd-cli on PATH does not appear to be the CUDA build. Run inside:
  nix shell $FLAKE_DIR#stable-diffusion-cpp-cuda nixpkgs#python3Packages.huggingface-hub
EOF
fi

mkdir -p "$MODEL_DIR"
cd "$MODEL_DIR"

# hf refuses to download gated repos without a token. Tell the user once
# instead of letting it fail mid-download.
if [[ ! -f "$HOME/.cache/huggingface/token" ]] \
   && [[ ! -f "$HOME/.cache/huggingface/stored_tokens" ]] \
   && [[ -z "${HF_TOKEN:-}" ]]; then
  cat >&2 <<'EOF'
no Hugging Face token found. Both kpsss34/FHDR_Uncensored and
black-forest-labs/FLUX.1-dev are gated. Run once:

  hf auth login

and accept the model license on huggingface.co for each repo.
EOF
  exit 1
fi

fetch() {
  local repo="$1" file="$2" dest="${3:-$2}"
  if [[ -f "$dest" ]]; then
    return 0
  fi
  echo ">> downloading $repo :: $file"
  hf download "$repo" "$file" --local-dir . >/dev/null
  # hf preserves the in-repo path; flatten it if requested.
  if [[ "$file" != "$dest" && -f "$file" ]]; then
    mv "$file" "$dest"
  fi
}

fetch "kpsss34/FHDR_Uncensored"           "$DIT_FILE"
fetch "comfyanonymous/flux_text_encoders" "clip_l.safetensors"
fetch "comfyanonymous/flux_text_encoders" "$T5_FILE"
# The FLUX VAE in black-forest-labs/FLUX.1-dev is gated. Comfy-Org's Lumina
# 2.0 repackaging ships the byte-identical ae.safetensors ungated, so we
# pull from there to spare a license-acceptance round trip.
fetch "Comfy-Org/Lumina_Image_2.0_Repackaged" \
      "split_files/vae/ae.safetensors" \
      "ae.safetensors"

# PRIME offload: razer14 keeps the dGPU in D3cold until a CUDA workload
# requests it. Without these the run silently falls back to CPU.
export __NV_PRIME_RENDER_OFFLOAD=1
export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __VK_LAYER_NV_optimus=NVIDIA_only
export CUDA_VISIBLE_DEVICES=0
export NVIDIA_VISIBLE_DEVICES=all
export NVIDIA_DRIVER_CAPABILITIES=compute,utility

OUTPUT_ABS="$(realpath -m "$OUTPUT")"
mkdir -p "$(dirname "$OUTPUT_ABS")"

EXTRA_FLAGS=()
[[ "$CLIP_ON_CPU" = "1" ]] && EXTRA_FLAGS+=(--clip-on-cpu)
[[ "$VAE_ON_CPU"  = "1" ]] && EXTRA_FLAGS+=(--vae-on-cpu)
[[ "$T5_ON_CPU"   = "1" ]] && EXTRA_FLAGS+=(--clip-on-cpu)  # sd-cli's CPU flag
                                                            # covers all text
                                                            # encoders incl. T5
[[ "$FLASH_ATTN"  = "1" ]] && EXTRA_FLAGS+=(--diffusion-fa)
[[ "$VAE_TILING"  = "1" ]] && EXTRA_FLAGS+=(--vae-tiling)

# Deduplicate (CLIP_ON_CPU + T5_ON_CPU both add --clip-on-cpu).
mapfile -t EXTRA_FLAGS < <(printf '%s\n' "${EXTRA_FLAGS[@]}" | awk '!seen[$0]++')

echo ">> rendering to $OUTPUT_ABS"
echo ">> prompt: $PROMPT"
echo ">> flags:  ${EXTRA_FLAGS[*]} $EXTRA_SD_ARGS"

# shellcheck disable=SC2086 # EXTRA_SD_ARGS is intentionally word-split
exec sd-cli \
  --diffusion-model "$DIT_FILE" \
  --clip_l          "clip_l.safetensors" \
  --t5xxl           "$T5_FILE" \
  --vae             "ae.safetensors" \
  --cfg-scale       "$CFG_SCALE" \
  --sampling-method "$SAMPLER" \
  --steps           "$STEPS" \
  -H "$HEIGHT" -W "$WIDTH" \
  --seed "$SEED" \
  -p "$PROMPT" \
  -o "$OUTPUT_ABS" \
  "${EXTRA_FLAGS[@]}" \
  -v $EXTRA_SD_ARGS
