# Findings

## 1. The ncmoe "expert cliff" rule

`--n-cpu-moe N` moves the first N MoE layers' expert weights to CPU RAM. On a 12GB card with a 16GB MoE model, GPU VRAM must hold: attention layers + shared experts + KV cache + compute buffers. As ctx grows, KV grows, squeezing experts out → **dynamic spill → PCIe thrashing → speed collapses 2-3×**.

**Verified rule**: the sweet-spot ncmoe shifts upward with ctx (32K→16, 64K→17, 128K→20, 258K→22) and speed only drops mildly (64→51 tok/s). Below the cliff, speed is 20-25 tok/s regardless of how close you are; the sweet spot is **the first stable point above the cliff**.

**Tuning recipe**:
1. Sweep ncmoe in ±2 steps at your target ctx
2. Find where speed jumps (cliff boundary)
3. Use that first stable value

## 2. Long-input prefill collapse & the q4_0 KV fix

At 258K ctx with q8_0 KV (2844 MiB), a 45K-token input takes 397s (113 tok/s). Halving KV to q4_0 (1422 MiB) restores prefill to 527 tok/s (85.5s). Mechanism: KV buffer size squeezes the attention/activation memory path; q4 halves it with negligible decode impact.

**Rule**: for very large contexts, prefer q4_0 KV over q8_0 when inputs are long. 64K ctx with q8_0 is still the best small-context prefill (649 tok/s) — don't jump to 258K unless you actually need >60K input.

## 3. q4_0 KV is Qwen-friendly

Unlike Gemma (KL 1.09 at q4 KV), Qwen3.6 MoE shows KL 0.10 overall at q4_0 KV — usable. Long-doc category degrades most (KL 0.581). If your workload is quality-critical long documents, use 64K q8 instead.

## 4. Benchmark hygiene (we got burned)

- Always kill stale servers before parameter tests (`Stop-Process -Name llama-server -Force`, verify /health fails, VRAM <1GB). Start-Process-spawned servers survive script-session kills → dual processes on 8080 → new process fails to load AND benchmarks hit the OLD server (fake data).
- Prompt cache makes consecutive similar requests look fast (61K input "in 32.7s" was cache). Use fresh content or `cache_prompt=false`.
- Environment noise ±20% between sessions (CPU boost states) — compare profiles within one session.
