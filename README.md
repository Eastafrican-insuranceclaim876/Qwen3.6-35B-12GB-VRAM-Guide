# Qwen3.6-35B-A3B on 12GB VRAM — Full Context Guide

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows-blue)]()
[![Model](https://img.shields.io/badge/model-Qwen3.6--35B--A3B-purple)]()
[![VRAM](https://img.shields.io/badge/VRAM-12GB-green)]()
[![Context](https://img.shields.io/badge/context-258K-orange)]()

> Run the full **258K native context** of Qwen3.6-35B-A3B (MoE, 3B active) on an **RTX 4070 SUPER 12GB** with llama.cpp — all benchmarked, all tunable, scripts included.

## Profiles at a glance

```
┌────────────────────────────────────────────────────────────────────┐
│            Qwen3.6-35B-A3B · one model, four profiles              │
├──────────┬────────────┬────────────┬───────────────────────────────┤
│ 32K      │ 64K        │ 128K       │ 258K (native max)             │
│ ncmoe 16 │ ncmoe 17   │ ncmoe 20   │ ncmoe 22 + q4_0 KV            │
│ 64.0 t/s │ 60.7 t/s   │ 55.3 t/s   │ 50.9 t/s · 45K input in 85s   │
│ chat     │ default    │ long docs  │ full native context           │
└──────────┴────────────┴────────────┴───────────────────────────────┘
```

## TL;DR — What we found (measured, not guessed)

| Finding | Numbers |
|---|---|
| **258K native context WORKS on 12GB** | decode **50.9 tok/s**, 45K-token input **85.5s** |
| **The "expert cliff"**: `--n-cpu-moe` sweet spot shifts with context | 32K→16, 64K→17, 128K→20, 258K→22 |
| **Long-input prefill collapse** (q8 KV) and its fix (**q4_0 KV**) | 45K input: **397s → 85.5s** (4.6×) |
| q4_0 KV is nearly lossless for Qwen (unlike Gemma) | KL 0.10 overall, decode unaffected |

**Bottom line**: with the right `--n-cpu-moe` + `--cache-type` combo, a 12GB card runs the entire 262K-token native context at ~51 tok/s. Most guides stop at 32K/64K — they are leaving 4× context on the table.

## Hardware / Stack

- GPU: NVIDIA RTX 4070 SUPER **12 GB** (192-bit, ~504 GB/s) — works on any 12GB+ card: 3060, 4060 Ti, 4070
- CPU: Intel i5-14600KF (6P+8E, 20 threads)
- RAM: 32 GB DDR4
- Backend: llama.cpp server (Windows-native CUDA build, **ik_llama.cpp b5095** — native Windows is 2-3× faster than WSL under VRAM pressure)
- Model: `Qwen3.6-35B-A3B` APEX/abliterated GGUF (~16 GB) + mmproj 902 MB
- OS: Windows 10/11

Full hardware/environment details + per-profile memory footprint: [benchmarks/hardware-env.md](benchmarks/hardware-env.md)
Full tuning history (every measurement, all failed variants): [benchmarks/tuning-history.md](benchmarks/tuning-history.md)

## Quick Start

### 0. Get the model (HF: SC117/Qwen3.6-35B-A3B-uncensored-heretic-Native-MTP-Preserved-APEX-GGUF)

| file | size | note |
|---|---|---|
| `Qwen3.6-35B-A3B-...-APEX-I-Compact.gguf` | 17.0 GB | **this guide's model** (q8-ish, fits 12GB with ncmoe offload) |
| `Qwen3.6-35B-A3B-...-APEX-I-MINI.gguf` | 14.3 GB | lighter option, more VRAM headroom |
| `Qwen3.6-35B-A3B-...-APEX-I-Balanced.gguf` | 26.0 GB | needs >12GB or heavy offload |
| `mmproj-Qwen3.6-35B-A3B-...-APEX-F16.gguf` | 0.9 GB | vision (optional) |

```bash
# with huggingface_hub
hf download SC117/Qwen3.6-35B-A3B-uncensored-heretic-Native-MTP-Preserved-APEX-GGUF \
  Qwen3.6-35B-A3B-uncensored-heretic-Native-MTP-Preserved-APEX-I-Compact.gguf --local-dir models/
# or China mirror
hf download --endpoint https://hf-mirror.com SC117/Qwen3.6-35B-A3B-uncensored-heretic-Native-MTP-Preserved-APEX-GGUF \
  Qwen3.6-35B-A3B-uncensored-heretic-Native-MTP-Preserved-APEX-I-Compact.gguf --local-dir models/
```

> The official **Qwen/Qwen3.6-35B-A3B** (Apache-2.0) also works — same tuning applies. The APEX/uncensored variant is what we benchmarked.

### 1. Get llama.cpp server

```bash
# official build (any recent version ≥ b5xxx works; flash-attn optional but not required)
git clone https://github.com/ggml-org/llama.cpp
cmake -B build -DGGML_CUDA=ON && cmake --build build --config Release
# → build/bin/Release/llama-server.exe
```

We used a Windows-native CUDA build (ik_llama.cpp b5095 fork). Native Windows beats WSL 2-3× under VRAM pressure — don't run this in WSL.

### 2. Start a profile

Pick a profile and run (PowerShell, idempotent — starts the server if not running):

```powershell
# Light tasks / chat (32K ctx, fastest: ~64 tok/s)
powershell -ExecutionPolicy Bypass -File scripts/ensure_qwen.ps1

# Default: compression & sub-agents (64K ctx, ~60.7 tok/s, lossless q8 KV)
powershell -ExecutionPolicy Bypass -File scripts/ensure_qwen_64k.ps1

# Long inputs up to 128K (~55.3 tok/s)
powershell -ExecutionPolicy Bypass -File scripts/ensure_qwen_128k.ps1

# FULL native context 258K (q4_0 KV, ~51 tok/s, 45K input in 85s)
powershell -ExecutionPolicy Bypass -File scripts/ensure_qwen_258k.ps1
```

Each script: checks port 8080 → starts `llama-server.exe` as an independent process → waits for health → prints status. Edit the `$ROOT` / `$MODEL` variables at the top for your paths.

Core command (258K profile):

```bash
llama-server.exe \
  -m <MODEL.gguf> \
  -ngl 99 --n-cpu-moe 22 -c 262144 \
  --cache-type-k q4_0 --cache-type-v q4_0 \
  --no-mmap --mlock \
  --reasoning off --reasoning-format deepseek \
  --jinja --threads 12 \
  --host 127.0.0.1 --port 8080
```

## Verify It Works

```bash
# 1. health check (should print {"status":"ok",...})
curl http://127.0.0.1:8080/health

# 2. quick chat test
curl http://127.0.0.1:8080/v1/chat/completions -H "Content-Type: application/json" \
  -d '{"model":"local","messages":[{"role":"user","content":"Say hi in one line"}],"max_tokens":50}'

# 3. speed benchmark (3 runs, prints tok/s; same-session comparison only)
python scripts/benchmark.py
```

Expected: `n_ctx` matches the profile (65536 / 131072 / 262144), decode ≈ 50-64 tok/s depending on profile.

## Benchmark Tables

### Context profiles (q8_0 KV, ncmoe = sweet spot, long-output ×3 average)

| ctx | KV size | ncmoe | decode tok/s | prefill (45K input) | use |
|---|---|---|---|---|---|
| 32K | ~590 MiB | 16 | **64.0** | — | light chat |
| 64K | ~742 MiB | 17 | **60.7** | 69.4s (649 tok/s) | default |
| 128K | ~1422 MiB | 20 | **55.3** | ~250 tok/s | long docs |
| 258K | ~2844 MiB (q8) / 1422 (q4) | 22 | **50.9 (q4)** | 85.5s (q4) | full native |

### The ncmoe "expert cliff" — 258K full scan

Sweeping `--n-cpu-moe` around the cliff at 258K ctx (q8 KV):

| ncmoe | 18 | 19 | 20 | 21 | **22** | 23 | 24 | 25 | 26 | 27 | 28 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| tok/s | 23.3 | 23.5 | 24.6 | 20.5 | **51.2** | 48.5 | 49.3 | 47.8 | 46.9 | 45.4 | 45.0 |

**Cliff at 21/22**: below 22 the GPU can't fit experts + KV → dynamic spill → PCIe thrashing (20-25 tok/s). The sweet spot is **the first stable point above the cliff** (22 here).

### The rule (verified across 4 context sizes)

> **As ctx grows, the sweet-spot `--n-cpu-moe` shifts upward** — 32K→16, 64K→17, 128K→20, 258K→22 — while speed only drops mildly (64→51 tok/s).

**Tuning recipe**: sweep ncmoe in ±2 steps to find the cliff boundary; the sweet spot = first point above it. `fa on` and large `-b 4096` batches are *negative* optimizations under VRAM offload.

### Long-input prefill collapse (and the q4_0 KV fix)

45K-token input, 258K ctx:

| config | time | effective prefill |
|---|---|---|
| q8_0 KV | **397s** ❌ | 113 tok/s |
| q8_0 KV + `-fa on` | >600s ❌ | worse |
| **q4_0 KV** | **85.5s** ✅ | **527 tok/s** |

Root cause: q8 KV at 258K occupies 2844 MiB, squeezing attention; halving KV to 1422 MiB with q4_0 restores fast prefill. **q4_0 KV does not slow decode** (50.9 vs 51.2) and is near-lossless for Qwen (KL ~0.10 overall; Gemma degrades to KL 1.09 — Qwen is unusually KV-quantization-friendly).

## Model capability (why this matters)

Qwen3.6-35B-A3B at 3B active params: SWE-bench Verified **73.4**, MCPMark **37.0** (2× Gemma4-31B), AIME 2026 **92.7**, C-Eval **90.0**. It's a legit agent/coding model that fits a 12GB card — a strong zero-cost tier for routine agent tasks.

## Troubleshooting (things we actually hit)

1. **Stale server on 8080 corrupts benchmarks** — Start-Process-spawned llama-server survives script-session kills. Before parameter tests: `Stop-Process -Name llama-server -Force`, confirm `/health` fails, VRAM < 1 GB.
2. **Prompt-cache fake speedups** — consecutive similar requests hit KV cache (61K input "in 32.7s" was cache). Benchmark with fresh content or `cache_prompt=false`.
3. **PS 5.1 `Start-Process` + `--chat-template-kwargs '{"..."}'`** — crashes the child with 0-byte logs. The flag is deprecated anyway; `--reasoning off` is enough.
4. **`--n-cpu-moe 99` (all experts CPU) OOMs** at 258K on 16GB-model/32GB-RAM — pinned-memory exhaustion. Don't copy 6GB-VRAM setups blindly.
5. **Vision note**: the VLM (mmproj) crashes on large images (`mtmd_decode -3`) — crop & enlarge before asking it to read figures.

## Files

```
Qwen3.6-35B-12GB-VRAM-Guide/
├── README.md
├── scripts/          # 4 profiles (32K/64K/128K/258K), paths templated
├── benchmarks/       # raw speed tables
└── docs/             # cliff rule, prefill collapse, troubleshooting
```

## Related Projects

- [MiniMax-H3-12GB-ComfyUI-Guide](https://github.com/shiqikuangsan31/MiniMax-H3-12GB-ComfyUI-Guide) — H3 video generation (T2V/I2V + synced audio, MotionContext) on the same 12GB rig. Together: **text/agent inference + video generation, both on 12GB VRAM**.

## License

MIT
