# Raw Benchmark Tables (measured 2026-08-11, RTX 4070 SUPER 12GB)

Environment: llama.cpp Windows CUDA build (b5095), 32GB DDR4, i5-14600KF.
Model: Qwen3.6-35B-A3B APEX GGUF (~16GB, uncensored variant). All speeds = 3×500-token runs, averaged. KV = q8_0 unless noted.

## Context profiles (ncmoe tuned per ctx)

| ctx | ncmoe | KV size | decode tok/s | notes |
|---|---|---|---|---|
| 8K | 16 | ~148 MiB | 63.1 | old default |
| 16K | 16 | ~296 MiB | 64.4 | |
| 32K | 16 | ~590 MiB | 64.0 | sweet spot, ~600 MiB VRAM left |
| 64K | 16 | 742.82 MiB | 25.6 | ❌ cliff (spill) |
| 64K | **17** | 742.82 MiB | **60.7** | ✅ sweet spot |
| 128K | 16 | 1422 MiB | 22.9 | ❌ cliff |
| 128K | **20** | 1422 MiB | **55.3** | ✅ |
| 258K | 20 | 2844 MiB | 24.6 | ❌ cliff |
| 258K | 22 (q8) | 2844 MiB | 51.2 | ✅ |
| 258K | 22 (q4_0) | 1422 MiB | **50.9** | ✅ + fast prefill |

## 258K ncmoe full scan (q8 KV)

| ncmoe | 18 | 19 | 20 | 21 | 22 | 23 | 24 | 25 | 26 | 27 | 28 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| tok/s | 23.3 | 23.5 | 24.6 | 20.5 | 51.2 | 48.5 | 49.3 | 47.8 | 46.9 | 45.4 | 45.0 |

Cliff boundary: 21/22.

## Long-input prefill (45K tokens, 258K ctx)

| config | total time | effective prefill |
|---|---|---|
| q8_0 KV, ncmoe 22 | 397.4s | 113 tok/s |
| q8_0 + -fa on | >600s | worse |
| q4_0 KV, ncmoe 22 | 85.5s | 527 tok/s |

64K ctx q8_0, same 45K task: 69.4s (649 tok/s) — best small-ctx prefill.

## Failed variants (negative results, all measured)

| variant | result |
|---|---|
| --n-cpu-moe 99 (all experts CPU), 128K/258K | OOM: pinned memory "resource already mapped" |
| -fa on (any offload config) | decode ~same, prefill worse |
| -b 4096 -ub 2048 | prefill 161 vs 252 tok/s (worse) |
| MTP speculative (--spec-type mtp) | 37.0 vs 63.1 tok/s (negative) |
| threads 20 | 60.2 vs 63.1 (slightly worse) |
| ncmoe 0 (all GPU) | 12.6 tok/s (VRAM spill) |

## q4_0 KV quality (localbench data, Qwen3.6-35B-A3B)

Overall KL 0.087-0.117 (usable; Gemma 26B-A4B reaches 1.088). Per-category at q4_0: long docs 0.581 (noticeable), tool calling 0.086, everything else ≈0. q8_0: KL 0.039 (near lossless). Decode speed unaffected by KV quant.
