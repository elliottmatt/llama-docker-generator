#!/bin/bash
set -euo pipefail

if [ -z "${1:-}" ]; then
    echo "Usage: $0 <image-tag>"
    echo "  e.g. $0 ghcr.io/yourname/llama-runpod:latest"
    exit 1
fi

TAG="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Building base image: $TAG"
docker build -t "$TAG" "$SCRIPT_DIR"

echo "==> Pushing $TAG ..."
docker push "$TAG"

echo "Done: $TAG"
