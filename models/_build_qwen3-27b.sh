#!/bin/bash
set -euo pipefail

TAG="ghcr.io/elliottmatt/llama-qwen3-27b:latest"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Building $TAG ..."
docker build -f "$SCRIPT_DIR/Dockerfile.qwen3-27b" -t "$TAG" "$SCRIPT_DIR"

echo "==> Pushing $TAG ..."
docker push "$TAG"

echo "Done: $TAG"
