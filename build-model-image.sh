#!/bin/bash
set -euo pipefail

usage() {
    cat <<EOF
Usage: $0 --base <base-image> --tag <image-tag> --model <repo:pattern> [--args "<llama-args>"] [--push]

  --base   Base image        e.g. ghcr.io/yourname/llama-runpod:latest
  --tag    Output image tag  e.g. ghcr.io/yourname/llama-qwen3-27b:latest
  --model  HF model          e.g. unsloth/Qwen3-27B-GGUF:Q4_K_M
  --args   llama-server flags to bake in  e.g. "-c 200000 -ctk q8_0 -ctv q8_0 -ngl 99"
  --push   Push after building (optional)

Examples:
  $0 --base ghcr.io/yourname/llama-runpod:latest \\
     --tag  ghcr.io/yourname/llama-qwen3-27b:latest \\
     --model unsloth/Qwen3-27B-GGUF:Q4_K_M \\
     --args "-c 200000 -ctk q8_0 -ctv q8_0 -ngl 99 --rope-scaling yarn" \\
     --push
EOF
    exit 1
}

BASE=""
TAG=""
MODEL_URL=""
LLAMA_ARGS=""
PUSH=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --base)  BASE="$2";       shift 2 ;;
        --tag)   TAG="$2";        shift 2 ;;
        --model) MODEL_URL="$2";  shift 2 ;;
        --args)  LLAMA_ARGS="$2"; shift 2 ;;
        --push)  PUSH=true;       shift   ;;
        *)       usage ;;
    esac
done

[ -z "$BASE" ] || [ -z "$TAG" ] || [ -z "$MODEL_URL" ] && usage

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cat > "$TMPDIR/Dockerfile" <<EOF
FROM ${BASE}
ENV MODEL_URL="${MODEL_URL}"
ENV LLAMA_ARGS="${LLAMA_ARGS}"
EOF

echo "==> Building $TAG ..."
echo "    Model : $MODEL_URL"
echo "    Args  : ${LLAMA_ARGS:-(none)}"
docker build -f "$TMPDIR/Dockerfile" -t "$TAG" "$TMPDIR"

if $PUSH; then
    echo "==> Pushing $TAG ..."
    docker push "$TAG"
fi

echo "Done: $TAG"
