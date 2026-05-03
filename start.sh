#!/bin/bash
set -euo pipefail

# ── Validate required env vars ────────────────────────────────────────────────
missing=()
for var in HF_TOKEN LLAMA_API_KEY MODEL_URL; do
    [ -z "${!var:-}" ] && missing+=("$var")
done
if [ ${#missing[@]} -gt 0 ]; then
    echo "ERROR: Missing required environment variables: ${missing[*]}"
    exit 1
fi

# ── HuggingFace login ─────────────────────────────────────────────────────────
echo "==> Logging into HuggingFace..."
huggingface-cli login --token "$HF_TOKEN" --quiet

# ── Parse MODEL_URL (format: hf_repo:filename_pattern) ───────────────────────
REPO="${MODEL_URL%%:*}"
PATTERN="${MODEL_URL#*:}"

if [ "$REPO" = "$MODEL_URL" ] || [ -z "$PATTERN" ]; then
    echo "ERROR: MODEL_URL must be 'hf_repo:filename_pattern', got: $MODEL_URL"
    echo "  Examples:"
    echo "    unsloth/Qwen3-27B-GGUF:Q4_K_M"
    echo "    unsloth/gemma-4-31B-it-GGUF:UD-Q6_K_XL"
    exit 1
fi

# ── Download model if not already cached ─────────────────────────────────────
REPO_SLUG=$(echo "$REPO" | tr '/' '__')
MODEL_DIR="/workspace/models/${REPO_SLUG}"
mkdir -p "$MODEL_DIR"

MODEL_FILE=$(find "$MODEL_DIR" -name "*${PATTERN}*.gguf" 2>/dev/null | sort | head -1)

if [ -z "$MODEL_FILE" ]; then
    echo "==> Downloading ${REPO} matching *${PATTERN}*.gguf ..."
    huggingface-cli download "$REPO" \
        --include "*${PATTERN}*.gguf" \
        --local-dir "$MODEL_DIR"
    MODEL_FILE=$(find "$MODEL_DIR" -name "*${PATTERN}*.gguf" | sort | head -1)
fi

if [ -z "$MODEL_FILE" ]; then
    echo "ERROR: No .gguf file found after download (repo: $REPO, pattern: *${PATTERN}*.gguf)"
    exit 1
fi

echo "==> Model: $MODEL_FILE"

# ── Start watchdog (shuts pod after 15 min idle) ──────────────────────────────
/watchdog.sh &

# ── Start llama-server on internal port (not publicly exposed) ────────────────
INTERNAL_PORT=8081
echo "==> Starting llama-server on internal port ${INTERNAL_PORT} ..."

llama-server \
    --model "$MODEL_FILE" \
    --host 127.0.0.1 \
    --port "$INTERNAL_PORT" \
    --api-key "$LLAMA_API_KEY" \
    ${LLAMA_ARGS:-} &

LLAMA_PID=$!

# ── Wait for llama-server to be ready ────────────────────────────────────────
echo "==> Waiting for llama-server to be ready..."
for i in $(seq 1 120); do
    if curl -sf "http://127.0.0.1:${INTERNAL_PORT}/health" > /dev/null 2>&1; then
        echo "==> llama-server ready"
        break
    fi
    if ! kill -0 "$LLAMA_PID" 2>/dev/null; then
        echo "ERROR: llama-server exited unexpectedly"
        exit 1
    fi
    sleep 2
done

# ── Start proxy on public port (foreground) ───────────────────────────────────
PUBLIC_PORT="${LLAMA_PORT:-8080}"
export LLAMA_INTERNAL_PORT="$INTERNAL_PORT"
exec python3 /proxy.py "$PUBLIC_PORT"
