#!/usr/bin/env bash
# install.sh — one-stop setup for flicker. Grows over time: every manual
# setup step lands here as a new section. Idempotent: safe to re-run,
# finished steps detect themselves and skip.
set -u

PILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 0. Prerequisites ---
# Refine (sections 1-2) needs llama-server; without it those sections are
# skipped, the rest still runs.
HAVE_LLAMA=1
command -v llama-server >/dev/null 2>&1 || {
  echo "warning: llama-server not found in PATH — skipping the Refine sections (1-2)" >&2
  HAVE_LLAMA=0
}

if [[ $HAVE_LLAMA == 1 ]]; then
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
fi # HAVE_LLAMA

# --- 3. Wallpapers (launcher carousel, wallr backend) ---
echo "3. wallpapers..."
# Tools: wallr = the wallpaper daemon; ffmpeg = thumbnails; magick =
# fill-blur composites; matugen = accent colour (optional); uv = the search
# server's Python env; Pillow = duplicate finder; gio = trash.
missing=()
for t in wallr ffmpeg magick uv gio python3; do
  command -v "$t" >/dev/null 2>&1 || missing+=("$t")
done
command -v matugen >/dev/null 2>&1 || echo "   note: matugen not found — the accent colour from the wallpaper stays off"
python3 -c "import PIL" 2>/dev/null || missing+=("python-pillow")
if (( ${#missing[@]} )); then
  echo "   missing: ${missing[*]}"
  echo "   install: sudo pacman -S --needed ffmpeg imagemagick uv glib2 python-pillow && yay -S wallr-bin"
fi

# 3a. Search model: visheratin/mexma-siglip2 (MIT) ONNX encoders, ~1 GB.
# Resumable into .part, sha256-checked against the Hugging Face LFS hashes.
SEM_DIR="$HOME/.local/share/flicker/models/mexma-siglip2"
SEM_URL="https://huggingface.co/visheratin/mexma-siglip2/resolve/main"
mkdir -p "$SEM_DIR"
declare -A SEM_SHA=(
  [mexma_image_encoder.onnx]=cca99950e01c9a49582a36a70208f840f372ff006d9aaf5345e7a9e78ba9b1c1
  [mexma_text_encoder.onnx]=305e0462b906670b8d5df2f020cfeb182bfe4aa3e00cc4493f9b3804ca685c8a
)
SEM_FILES=(mexma_image_encoder.onnx mexma_text_encoder.onnx tokenizer.json tokenizer_config.json
  special_tokens_map.json sentencepiece.bpe.model preprocessor_config.json config.json)
for f in "${SEM_FILES[@]}"; do
  out="$SEM_DIR/$f"
  [[ -s "$out" ]] && continue
  echo "   downloading $f..."
  for try in 1 2 3 4 5; do
    curl -sfL -C - -o "$out.part" "$SEM_URL/$f" && break
    echo "   retry $try..."
  done
  sha=${SEM_SHA[$f]:-}
  if [[ -n "$sha" ]] && ! echo "$sha  $out.part" | sha256sum -c --quiet 2>/dev/null; then
    echo "   error: $f checksum mismatch (kept as $out.part, re-run to resume)" >&2
    continue
  fi
  [[ -s "$out.part" ]] && mv "$out.part" "$out"
done
echo "   search model: $SEM_DIR"

# 3b. The search server's Python deps into uv's cache, so the shell can start
# it offline (WallpaperSemantic runs `uv run --offline` first).
if command -v uv >/dev/null 2>&1; then
  if RUST_LOG=warn uv sync --quiet --script "$PILL_DIR/scripts/wallpapers/clip.py"; then
    echo "   search server env ready"
  else
    echo "   warning: could not prepare the clip.py env (it is retried online on first use)"
  fi
  # Shazam (services/Shazam): same offline-first start; records with parecord.
  if RUST_LOG=warn uv sync --quiet --script "$PILL_DIR/scripts/shazam/recognize.py"; then
    echo "   shazam env ready"
  else
    echo "   warning: could not prepare the shazam env (it is retried online on first use)"
  fi
fi

# 3c. Folder and autostart hints (nothing is changed here).
[[ -d "$HOME/Pictures/Wallpapers" ]] || echo "   note: ~/Pictures/Wallpapers does not exist (launcher.wallpapers.dirs)"
for f in "$HOME/.config/driftwm/config.toml" "$HOME/.config/niri/config.kdl"; do
  [[ -f "$f" ]] || continue
  if ! grep -rqs "wallr daemon" "$f" "$(dirname "$f")/modules"; then
    echo "   note: $f does not autostart \"wallr daemon\" (wallpapers need the daemon running)"
  fi
done

echo "done. toggle dictation and watch 'refine server ready' in the qslog."
