# Hardware & Environment (measured on this rig)

## Hardware

| Component | Spec | Notes |
|---|---|---|
| GPU | NVIDIA RTX 4070 SUPER **12 GB** GDDR6X | 192-bit bus, ~504 GB/s; AD104, 7168 CUDA cores |
| CPU | Intel i5-14600KF | 6P+8E cores, 20 threads |
| RAM | 32 GB DDR4 | dual-channel, ~50 GB/s effective |
| Storage | NVMe SSD | model files ~17 GB total |

> **Why this rig matters**: 12GB VRAM + 32GB RAM is the most common "I can't run big LLMs" configuration. Everything here is validated on exactly that budget — no 24GB cards, no Mac Studios.

## Software

| Component | Version / Note |
|---|---|
| OS | Windows 10/11 (build 26100) |
| Backend | llama.cpp server, Windows-native CUDA build (**ik_llama.cpp b5095**) — NOT WSL (native Windows is 2-3× faster under VRAM pressure) |
| CUDA | 12.x runtime (bundled with build) |
| Model | `Qwen3.6-35B-A3B` APEX GGUF, ~16 GB (q8-ish weights, uncensored/abliterated variant) |
| Vision mmproj | `mmproj-Qwen3.6-35B-A3B` GGUF, 902 MB |

## Memory footprint (per profile)

| Profile | ctx | KV (q8_0) | KV (q4_0) | VRAM used (total) | headroom |
|---|---|---|---|---|---|
| 32K | 32768 | ~590 MiB | ~295 MiB | ~11.0 GB | ~1.2 GB |
| 64K | 65536 | ~743 MiB | ~371 MiB | ~11.3 GB | ~1.0 GB |
| 128K | 131072 | 1422 MiB | 711 MiB | ~11.7 GB | ~0.6 GB |
| 258K | 262144 | 2844 MiB | 1422 MiB | ~11.8 GB (q4) | ~0.5 GB |

Model weights (~16 GB) are split GPU/CPU via `--n-cpu-moe`; system RAM holds the CPU-side experts (mlock'd).

## Performance ceiling notes

- **GPU utilization during decode: only ~50%** (peak 52%). This is inherent to MoE+offload: only 8 of 256 experts activate per token; the GPU idles while 16 CPU-side experts + PCIe transfers run.
- Bottleneck = **PCIe transfer + DDR4 bandwidth**, not compute. Compute accelerators (fa on, bigger batch, SageAttention-style kernels) all made it *slower* — they add memory traffic under offload.
- decode ≈ **50-64 tok/s** depending on profile; prefill 250-650 tok/s depending on ctx/KV config.
