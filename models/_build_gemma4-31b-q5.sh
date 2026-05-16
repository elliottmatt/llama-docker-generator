#!/bin/bash
set -euo pipefail

TAG="ghcr.io/elliottmatt/llama-gemma4-31b-q5:latest"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Building $TAG ..."
docker build -f "$SCRIPT_DIR/Dockerfile.gemma4-31b-q5" -t "$TAG" "$SCRIPT_DIR"

echo "==> Pushing $TAG ..."
docker push "$TAG"

echo "Done: $TAG"
