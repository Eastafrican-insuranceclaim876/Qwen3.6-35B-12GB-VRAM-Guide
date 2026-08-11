# Full Tuning History (every measurement, 2026-08-11)

All runs: 3×500-token generations averaged, `--reasoning off`, q8_0 KV unless noted, same session for fair comparison.

## Context ladder (ncmoe = sweet spot per ctx)

| ctx | KV size | ncmoe | decode tok/s | VRAM used | judgment |
|---|---|---|---|---|---|
| 8192 | ~148 MiB | 16 | 63.1 | — | old default |
| 16384 | ~296 MiB | 16 | 64.4 | — | zero loss |
| 32768 | ~590 MiB | 16 | **64.0** | 11.0 GB | sweet spot (32K) |
| 65536 | 743 MiB | 16 | 25.6 | — | ❌ cliff |
| 65536 | 743 MiB | **17** | **60.7** | 11.3 GB | ✅ sweet spot (64K) |
| 131072 | 1422 MiB | 16 | 22.9 | — | ❌ cliff |
| 131072 | 1422 MiB | **20** | **55.3** | 11.7 GB | ✅ sweet spot (128K) |
| 262144 | 2844 MiB | 22 | 51.2 | 11.8 GB | ✅ sweet spot (258K, q8) |
| 262144 | 1422 MiB (q4) | 22 | **50.9** | 11.8 GB | ✅ recommended (258K, q4) |

**Rule**: sweet-spot ncmoe shifts up with ctx: 16 → 17 → 20 → 22. Speed only drops 64 → 51.

## 64K ncmoe scan (finding the cliff)

| ncmoe | 16 | 17 | 18 | 20 |
|---|---|---|---|---|
| tok/s | 25.6 ❌ | **60.7** ✅ | 58.8 | 57.0 |

`fa on` at ncmoe 16: 25.3 (no help).

## 128K ncmoe scan

| ncmoe | 16 | 20 | 22 |
|---|---|---|---|
| tok/s | 22.9 ❌ | **55.3** ✅ | 51.9 |

q4_0 KV at ncmoe 16: 26.2 (better than q8's 22.9, but tuning ncmoe beats quantizing KV).

## 258K full scan (every point, q8 KV)

| ncmoe | 18 | 19 | 20 | 21 | **22** | 23 | 24 | 25 | 26 | 27 | 28 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| tok/s | 23.3 | 23.5 | 24.6 | 20.5 | **51.2** | 48.5 | 49.3 | 47.8 | 46.9 | 45.4 | 45.0 |

Cliff boundary: 21/22. Below 22 = dynamic expert spill (20-25 tok/s flat); above 22 = monotonic slow decline (more CPU experts → slower).

## Long-input prefill (45K tokens, 258K ctx)

| config | total | effective prefill |
|---|---|---|
| q8_0 KV | 397.4s | 113 tok/s |
| q8_0 + `-fa on` | >600s (timed out) | worse |
| **q4_0 KV** | **85.5s** | **527 tok/s** |

64K q8_0 same task: 69.4s (649 tok/s) — best small-ctx prefill.
Prompt-cache effect: a 61K input with cached prefix took 32.7s (cache hit, not real prefill).

## Accelerator variants (all measured, all negative on 12GB)

| variant | decode tok/s | verdict |
|---|---|---|
| baseline (ncmoe 16, mlock, threads 12) | 63.1 | ✅ best |
| `--n-cpu-moe 0` (all experts GPU) | 12.6 | ❌ VRAM spill |
| `--n-cpu-moe 12` no `--mlock` | 16.3 | ❌ cliff + paging |
| MTP speculative (`--spec-type mtp:n_max=2`) | 37.0 | ❌ draft overhead > 51% accept |
| `--threads 20` | 60.2 | ❌ slightly worse |
| `-fa on` | 25.3 (64K ncmoe16) | ❌ workspace squeeze |
| `-b 4096 -ub 2048` | prefill 161 vs 252 | ❌ bigger batch worse |
| `--n-cpu-moe 99` (all experts CPU) | OOM | ❌ pinned-memory exhaustion (16GB model + 32GB RAM insufficient) |

## Vision mode (mmproj)

| test | result |
|---|---|
| text speed with mmproj loaded | 59.7 tok/s (−5%) |
| full image (2432×1500) | **crash** (`mtmd_decode -3`, ~200s encode then fail) |
| cropped/enlarged small figure | 17-18s, reads numbers accurately |
| 3 consecutive images | server becomes unstable, needs restart |

**VLM rule**: crop & enlarge figures before asking it to read them; fine for single small images, not for batch/large.

## q4_0 KV quality (from localbench KV-quant benchmark, Qwen3.6-35B-A3B)

| KV | overall KL | long docs | tool calling | other |
|---|---|---|---|---|
| q8_0 | 0.039 | 0.142 | ~0 | ~0 |
| q4_0 | 0.087-0.117 | **0.581** | 0.086 | ~0 |

Qwen is exceptionally KV-quant-friendly (Gemma 26B-A4B hits KL 1.088 at q4). Decode speed unaffected by KV quant. If long-doc quality is critical, use 64K q8 profile instead of 258K q4.

## Environment noise warning

Same config measured in different sessions: 31.9 vs 25.6 tok/s (±20%, CPU boost states). Compare profiles within ONE session; treat absolute numbers as indicative.
