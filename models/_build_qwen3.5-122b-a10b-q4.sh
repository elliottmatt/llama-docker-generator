#!/bin/bash
set -euo pipefail

TAG="ghcr.io/elliottmatt/llama-qwen3.5-122b-a10b-q4:latest"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Building $TAG ..."
docker build -f "$SCRIPT_DIR/Dockerfile.qwen3.5-122b-a10b-q4" -t "$TAG" "$SCRIPT_DIR"

echo "==> Pushing $TAG ..."
docker push "$TAG"

echo "Done: $TAG"
