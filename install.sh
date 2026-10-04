#!/usr/bin/env bash
# install.sh — one-stop setup for pillShell. Grows over time: every manual
# setup step lands here as a new section. Idempotent: safe to re-run,
# finished steps detect themselves and skip.
set -u

PILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 0. Prerequisites ---
command -v llama-server >/dev/null 2>&1 || {
  echo "error: llama-server not found in PATH (Refine needs it)" >&2
  exit 1
}

# --- 1. Refine model (Gemma 4 E2B Q4_0, ~2.7 GB, public repo, no auth) ---
MODEL_DIR="$HOME/.cache/llama"
MODEL_FILE="$MODEL_DIR/gemma-4-E2B-it-Q4_0.gguf"
MODEL_PART="$MODEL_FILE.part"
MODEL_URL="https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_0.gguf?download=true"
if [[ -s "$MODEL_FILE" ]]; then
  echo "1. model present, skipping download: $MODEL_FILE"
  echo "   (delete it to force re-download)"
else
  echo "1. downloading Refine model (~2.7 GB, resumable into .part)..."
  mkdir -p "$MODEL_DIR"
  # Into .part first: an interrupted run never looks complete, and -C -
  # resumes it. Atomic mv only on curl success.
  curl -L -C - -o "$MODEL_PART" "$MODEL_URL" && mv "$MODEL_PART" "$MODEL_FILE"
fi

# --- 2. Enable Refine in the live config (config.json is git-ignored) ---
echo "2. enabling Refine in config.json..."
PILL_DIR="$PILL_DIR" python3 - <<'EOF'
import json
import os
p = os.path.join(os.environ["PILL_DIR"], "config", "config.json")
cfg = json.load(open(p))
d = cfg["dictation"]
d["refineEnabled"] = True
d["refineModel"] = "gemma-4-E2B-it-Q4_0"
d["refineServerCommand"] = (
    "llama-server -m ~/.cache/llama/gemma-4-E2B-it-Q4_0.gguf"
    " --port 8080 -c 4096 -t 4 -np 1 --reasoning off"
)
# Atomic write: a crash mid-dump must never leave a truncated config.
tmp = p + ".tmp"
json.dump(cfg, open(tmp, "w"), ensure_ascii=False, indent=2)
os.replace(tmp, p)
print("   refineEnabled=true, server managed by the shell")
EOF

echo "done. toggle dictation and watch 'refine server ready' in the qslog."
