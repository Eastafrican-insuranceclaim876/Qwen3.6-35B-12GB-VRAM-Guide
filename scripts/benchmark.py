#!/usr/bin/env python3
"""Quick decode-speed benchmark for a llama.cpp server (OpenAI-compatible endpoint).

Usage:
    python benchmark.py [port] [runs]

Notes:
    - Compare profiles within ONE session only (environment noise ±20% between sessions).
    - Consecutive similar prompts hit the KV prompt cache and fake fast results.
      This script randomizes the prompt each run to avoid that.
    - Expect 50-64 tok/s on a 12GB card with the tuned profiles from this repo.
"""
import json
import random
import statistics
import sys
import time
import urllib.request

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
RUNS = int(sys.argv[2]) if len(sys.argv) > 2 else 3
BASE = f"http://127.0.0.1:{PORT}"

TOPICS = [
    "forest carbon cycling and photosynthesis",
    "soil organic carbon dynamics",
    "litter decomposition in temperate forests",
    "atmospheric CO2 exchange and eddy covariance",
    "sustainable forest management practices",
]


def run_once(prompt: str) -> tuple[float, int, int]:
    payload = {
        "model": "local",
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 500,
        "temperature": 0.7,
    }
    req = urllib.request.Request(
        BASE + "/v1/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=300) as r:
        d = json.loads(r.read().decode())
    dt = time.time() - t0
    u = d["usage"]
    return u["completion_tokens"] / dt, u["prompt_tokens"], u["completion_tokens"]


def main():
    try:
        with urllib.request.urlopen(BASE + "/health", timeout=5) as r:
            assert json.loads(r.read())["status"] == "ok"
    except Exception as e:
        print(f"server not healthy on :{PORT} — {e}")
        sys.exit(1)

    speeds = []
    for i in range(RUNS):
        # randomize topic so prompt cache can't fake the number
        prompt = (
            f"请详细论述{TOPICS[(i + random.randint(0, len(TOPICS) - 1)) % len(TOPICS)]}"
            "，从五个方面各100字以上，学术中文。"
        )
        tok_s, pt, ct = run_once(prompt)
        speeds.append(tok_s)
        print(f"Run {i+1}: {tok_s:.1f} tok/s (prompt {pt} tok, output {ct} tok)")
        time.sleep(0.5)

    print(f"\nmean: {statistics.mean(speeds):.1f} tok/s  (median {statistics.median(speeds):.1f})")


if __name__ == "__main__":
    main()
