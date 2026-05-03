# llama-docker-generator

Docker setup for running [llama.cpp](https://github.com/ggml-org/llama.cpp) on [RunPod](https://runpod.io) with an RTX 5090 (Blackwell).

## What it does

- Builds llama.cpp from source at image build time with CUDA 13.1 + Flash Attention targeting sm_120 (RTX 5090)
- Downloads any GGUF model from HuggingFace on first boot, caches it in `/workspace/models`
- Serves an OpenAI-compatible HTTP API on port 8080, protected by an API key
- Ships `runpodctl`, `tmux`, and `nvtop` for pod management and monitoring

## Image architecture

```
nvidia/cuda:13.1.0-devel-ubuntu22.04   (builder — compile llama.cpp)
        │
        └─▶  nvidia/cuda:13.1.0-runtime-ubuntu22.04  (runtime — your final image)
                    + compiled llama-server / llama-cli binaries
                    + huggingface-cli, runpodctl, tmux, nvtop
                    + start.sh entrypoint
```

Per-model images are a thin layer on top of the base:

```
ghcr.io/yourname/llama-runpod:latest   (base)
        │
        └─▶  ghcr.io/yourname/llama-qwen3-27b:latest
                    ENV MODEL_URL="unsloth/Qwen3-27B-GGUF:Q4_K_M"
                    ENV LLAMA_ARGS="-c 200000 -ctk q8_0 ..."
```

## Prerequisites

- Docker with BuildKit
- NVIDIA Container Toolkit installed on your build machine (for the CUDA build stage)
- Authenticated to `ghcr.io`:
  ```bash
  echo $GITHUB_TOKEN | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
  ```

## Usage

### 1. Build and push the base image

Do this once, and again whenever you want to update llama.cpp to a newer master commit.

```bash
./build-base.sh ghcr.io/yourname/llama-runpod:latest
```

### 2. Build a per-model image

Bakes the model URL and llama-server flags into the image so you don't have to pass them at runtime.

```bash
./build-model-image.sh \
  --base  ghcr.io/yourname/llama-runpod:latest \
  --tag   ghcr.io/yourname/llama-qwen3-27b:latest \
  --model "unsloth/Qwen3-27B-GGUF:Q4_K_M" \
  --args  "-c 200000 -ctk q8_0 -ctv q8_0 -ngl 99 --rope-scaling yarn" \
  --push
```

Model examples:
| Model | `--model` value | Fits single 5090? |
|---|---|---|
| Qwen3 27B | `unsloth/Qwen3-27B-GGUF:Q4_K_M` | Yes |
| Qwen3 35B-A3B (MoE) | `unsloth/Qwen3-35B-A3B-GGUF:UD-Q5_K_XL` | Yes |
| Gemma 4 31B | `unsloth/gemma-4-31B-it-GGUF:UD-Q6_K_XL` | Yes, tight |

### 3. Deploy on RunPod

In your RunPod pod template:

| Field | Value |
|---|---|
| Container image | `ghcr.io/yourname/llama-qwen3-27b:latest` |
| Expose port | `8080` |
| GPU | RTX 5090 |

Set these environment variables in the RunPod template or at pod launch:

| Variable | Required | Description |
|---|---|---|
| `HF_TOKEN` | Yes | HuggingFace API token (for gated models) |
| `LLAMA_API_KEY` | Yes | Bearer token clients must send to use the API |
| `MODEL_URL` | Baked in | Set by `build-model-image.sh` — can override at runtime |
| `LLAMA_ARGS` | Baked in | Set by `build-model-image.sh` — can override at runtime |
| `LLAMA_PORT` | No | Defaults to `8080` |

The server **will not start** if `LLAMA_API_KEY` is unset. Do not run without it — the API is internet-exposed.

### 4. Call the API

```bash
curl https://<your-runpod-endpoint>/v1/chat/completions \
  -H "Authorization: Bearer YOUR_LLAMA_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "local",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

## Context length and VRAM

The RTX 5090 has 32 GB VRAM. At 200k context, KV cache is the dominant cost.
Recommended flags for long-context use:

```
-c 200000          context size
-ctk q8_0          quantize KV cache keys   (50% VRAM vs fp16, negligible quality loss)
-ctv q8_0          quantize KV cache values
-ngl 99            offload all layers to GPU
--rope-scaling yarn extend context beyond training limit
```

Approximate VRAM usage at 200k context (single 5090):

| Model | Quant | Model VRAM | KV q8_0 | Total | Fits? |
|---|---|---|---|---|---|
| Qwen3 27B | Q4_K_M | ~17 GB | ~14 GB | ~31 GB | Barely |
| Qwen3 35B-A3B (MoE) | Q4_K_M | ~20 GB | ~10 GB | ~30 GB | Yes |
| Gemma 4 31B | Q4_K_M | ~19 GB | ~16 GB | ~35 GB | Too tight |

## Multi-GPU

The same image works with multiple GPUs. Add `--tensor-split 1,1` to `LLAMA_ARGS` for equal split across two GPUs. No image changes needed.

## Updating llama.cpp

Rebuild and push the base image. Then rebuild any per-model images on top of it.

```bash
./build-base.sh ghcr.io/yourname/llama-runpod:latest
./build-model-image.sh --base ghcr.io/yourname/llama-runpod:latest --tag ... --model ... --push
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Multi-stage build: compile llama.cpp, produce lean runtime image |
| `start.sh` | Container entrypoint: login, download model, launch server |
| `build-base.sh` | Build and push the base image |
| `build-model-image.sh` | Generate and push a per-model image with baked settings |
