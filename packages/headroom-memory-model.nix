{ pkgs }:
let
  # Match Headroom 0.37.0's immutable onnx_runtime._PINNED_REVISIONS entry,
  # not HuggingFace main: local-only lookup requests that exact snapshot.
  revision = "5f1b8cd78bc4fb444dd171e59b18f3a3af89a079";
  base = "https://huggingface.co/Qdrant/all-MiniLM-L6-v2-onnx/resolve/${revision}";
  model = pkgs.fetchurl {
    url = "${base}/model.onnx";
    hash = "sha256-u9e0ZvbVjmRv3CvV/Wey9ek8C2hwEb1FSMQg971G8MU=";
  };
  tokenizer = pkgs.fetchurl {
    url = "${base}/tokenizer.json";
    hash = "sha256-2g55kzue1ReYo64niT08X6SiARJs73VYYpbfm00sYqA=";
  };
in
pkgs.runCommand "headroom-memory-model-cache" { } ''
  root="$out/models--Qdrant--all-MiniLM-L6-v2-onnx"
  mkdir -p "$root/refs" "$root/snapshots/${revision}"
  printf '%s' '${revision}' > "$root/refs/main"
  ln -s ${model} "$root/snapshots/${revision}/model.onnx"
  ln -s ${tokenizer} "$root/snapshots/${revision}/tokenizer.json"
''
