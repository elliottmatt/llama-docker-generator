# ── Stage 1: Builder ─────────────────────────────────────────────────────────
FROM nvidia/cuda:13.0.0-devel-ubuntu22.04 AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        ninja-build \
        git \
        libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/ggml-org/llama.cpp /llama.cpp

WORKDIR /llama.cpp

# libcuda.so.1 is injected by the NVIDIA runtime at container start, not at build time.
# Point cmake at the stub library so linking succeeds; the real driver is used at runtime.
RUN ln -sf /usr/local/cuda/lib64/stubs/libcuda.so /usr/local/cuda/lib64/stubs/libcuda.so.1 \
    && cmake -B build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DGGML_CUDA=ON \
        -DGGML_FLASH_ATTN=ON \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_CUDA_ARCHITECTURES=120 \
        -DCMAKE_EXE_LINKER_FLAGS="-Wl,-rpath-link,/usr/local/cuda/lib64/stubs" \
        -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-rpath-link,/usr/local/cuda/lib64/stubs" \
    && cmake --build build --target llama-server llama-cli


# ── Stage 2: Runtime ─────────────────────────────────────────────────────────
FROM nvidia/cuda:13.0.0-runtime-ubuntu22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        wget \
        tmux \
        nvtop \
        libgomp1 \
        libcurl4 \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir "huggingface-hub[cli]" "aiohttp"

RUN wget -qO- cli.runpod.net | bash

COPY --from=builder /llama.cpp/build/bin/llama-server /usr/local/bin/llama-server
COPY --from=builder /llama.cpp/build/bin/llama-cli    /usr/local/bin/llama-cli

COPY start.sh    /start.sh
COPY proxy.py    /proxy.py
COPY watchdog.sh /watchdog.sh
RUN chmod +x /start.sh /watchdog.sh

WORKDIR /workspace
EXPOSE 8080

ENTRYPOINT ["/start.sh"]
