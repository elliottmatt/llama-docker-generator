# Docker Container Specs — RunPod / RTX 5090 / llama.cpp

## Base Image

**OS:** Ubuntu 22.04 LTS
**Base image:** `nvidia/cuda:13.1.0-devel-ubuntu22.04`
- CUDA 13.1 — locked, no fallback
- `-devel` variant includes nvcc, headers, and static libs required to compile llama.cpp with CUDA
- `nvidia-smi` is available via host driver passthrough (NVIDIA Container Toolkit) — no separate install needed

---

## Container Registry

**Registry:** GitHub Container Registry (`ghcr.io/<your-github-username>/<image-name>`)
- Already available with your GitHub account — no new signup
- Private by default
- Authenticate with your existing GitHub personal access token
- Recommended over Docker Hub (Docker Hub free tier limits private repos to 1)

---

## Workspace / Storage

- RunPod mounts persistent storage at **`/workspace`** by default
- Models downloaded to `/workspace/models/`
- llama.cpp cloned and compiled into `/workspace/llama.cpp/` on every container start

---

## Components to Install (at image build time)

### System Dependencies
- `build-essential`, `cmake`, `ninja-build`, `git`, `curl`, `wget`
- `python3`, `python3-pip`
- `libcurl4-openssl-dev`, `libgomp1`
- `tmux`
- `nvtop`

### HuggingFace CLI
- Installed via pip: `huggingface-hub[cli]`
- Token passed in as env var `HF_TOKEN`; login run at container start

### runpodctl
- Version: v2.2.0 (latest as of 2026-04-30)
- Install method: `wget -qO- cli.runpod.net | sudo bash`

### llama.cpp (multi-stage build)
- **Stage 1 (builder):** `nvidia/cuda:13.1.0-devel-ubuntu22.04`
  - Clone `https://github.com/ggml-org/llama.cpp` master (`--depth 1`)
  - Build with CMake + Ninja: `-DGGML_CUDA=ON -DGGML_FLASH_ATTN=ON -DCMAKE_CUDA_ARCHITECTURES=120`
  - Targets: `llama-server`, `llama-cli`
- **Stage 2 (runtime):** `nvidia/cuda:13.1.0-runtime-ubuntu22.04`
  - Copy only compiled binaries from builder (`/llama.cpp/build/bin/`)
  - Install runtime system deps only (no compilers, no headers)
  - Result: ~4-6 GB image vs ~12 GB if using devel throughout

---

## Model Download

Models are specified as a HuggingFace repo + filename pattern via the `MODEL_URL` env var:

**Format:** `{hf_repo}:{gguf_filename_or_glob}`

**Examples:**
```
unsloth/Qwen3.6-27B-GGUF:Q6_K
unsloth/gemma-4-31B-it-GGUF:UD-Q6_K_XL
unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q5_K_XL
```

The startup script will:
1. Parse `MODEL_URL` into repo (`unsloth/Qwen3.6-27B-GGUF`) and file pattern (`*Q6_K*.gguf`)
2. Run `huggingface-cli download <repo> --include "<pattern>" --local-dir /workspace/models/`
3. Locate the downloaded `.gguf` file and pass it to `llama-server`
4. If a matching file already exists in `/workspace/models/`, skip download

---

## Environment Variables

| Variable | Purpose | Required | Default |
|---|---|---|---|
| `HF_TOKEN` | HuggingFace API token for gated model access | Yes | — |
| `LLAMA_API_KEY` | Bearer token clients must send to use the API | Yes | — |
| `MODEL_URL` | HuggingFace model in `repo:filename` format | Yes | — |
| `LLAMA_PORT` | Port for llama-server HTTP API | No | `8080` |
| `LLAMA_ARGS` | Extra flags appended to llama-server at startup | No | — |

**Security:** If `LLAMA_API_KEY` is unset or empty, the startup script will **refuse to start `llama-server`** and print an error. The server is internet-exposed and must not run unauthenticated.

All requests to the API must include `Authorization: Bearer <LLAMA_API_KEY>`.

---

## Networking

- llama.cpp HTTP server on port **8080** (fixed; overridable via `LLAMA_PORT`)
- OpenAI-compatible REST API (`/v1/chat/completions`, `/v1/completions`, etc.)
- RunPod exposes ports via its reverse proxy — expose port 8080 in the RunPod template

---

## Deployment Type

**Pod** (not Serverless)
- SSH-accessible
- Persistent across restarts (data in `/workspace` survives pod stop/start)
- Container kept alive after startup completes

---

## Entrypoint / Startup Sequence (`start.sh`)

1. Validate required env vars (`HF_TOKEN`, `LLAMA_API_KEY`, `MODEL_URL`) — abort with error if any missing
2. `huggingface-cli login --token $HF_TOKEN`
3. Parse `MODEL_URL` into `REPO` and `PATTERN` (split on first `:`)
4. Check `/workspace/models/` for existing file matching `*PATTERN*.gguf` — skip download if found
5. If not found: `huggingface-cli download $REPO --include "*PATTERN*.gguf" --local-dir /workspace/models/...`
6. Locate the downloaded `.gguf` (first shard if multi-part)
7. `exec llama-server --model <path> --host 0.0.0.0 --port $LLAMA_PORT --api-key $LLAMA_API_KEY $LLAMA_ARGS`
8. Server runs in foreground; SSH remains available via RunPod alongside it

## Scripts

### `build-base.sh`
Builds and pushes the base image to ghcr.io. Takes the image tag as argument.

### `build-model-image.sh`
Generates a minimal 3-line Dockerfile (`FROM base` + two `ENV` lines), builds it, and optionally pushes.
Args: `--base`, `--tag`, `--model`, `--args`, `--push`

---

## Open Questions

1. **llama-server inference settings:** What defaults do you want baked into the image for model-specific params (context length, temperature, min_p, top_k, etc.)? These can be passed via `LLAMA_ARGS` at runtime, or we can bake per-model defaults into derived images pushed to `ghcr.io`. Which approach?

2. **Derived images workflow:** For per-model images (baked settings + no need to re-specify `MODEL_URL`), do you want a second `Dockerfile.model` that inherits from the base and sets `ENV MODEL_URL=...` and `ENV LLAMA_ARGS=...`? This lets you push e.g. `ghcr.io/you/llama-qwen3-27b:latest` with all settings locked in.

3. **GPU count / tensor parallelism:** Will you always run a single GPU on RunPod, or do you anticipate multi-GPU pods? llama.cpp supports `-ngl` (GPU layers) and tensor split flags.
