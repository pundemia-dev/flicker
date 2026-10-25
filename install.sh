#!/usr/bin/env bash
# install.sh — one-stop setup for Flicker. Grows over time: every manual
# setup step lands here as a new section. Idempotent: safe to re-run,
# finished steps detect themselves and skip. Never uses sudo itself: steps
# that need root print the exact command instead.
set -u

FLICKER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$FLICKER_DIR/config/config.json"

have() { command -v "$1" >/dev/null 2>&1; }

# --- 0. Dependencies (checked, not installed) ---
# Arch package per command; the shell starts without the optional ones, the
# feature in the comment just stays dead.
echo "0. dependencies..."
declare -A PKG=(
  [quickshell]=quickshell [grim]=grim [wl-copy]=wl-clipboard [wpctl]=wireplumber
  [pw-record]=pipewire-audio [parecord]=libpulse [pactl]=libpulse
  [brightnessctl]=brightnessctl [nmcli]=networkmanager [upower]=upower
  [bluetoothctl]=bluez-utils [notify-send]=libnotify [xdg-open]=xdg-utils
  [xdg-user-dir]=xdg-user-dirs [curl]=curl [jq]=jq [ffmpeg]=ffmpeg
  [magick]=imagemagick [python3]=python [file]=file [gio]=glib2
  [fuser]=psmisc [lsblk]=util-linux [udisksctl]=udisks2 [pkexec]=polkit
  [openssl]=openssl [zip]=zip [bsdtar]=libarchive [pdftoppm]=poppler
  # capture: recording, OCR, code scan
  [wf-recorder]=wf-recorder [tesseract]=tesseract [zbarimg]=zbar
  # optional: clipboard history, typing (dictation), visualizer, app launch, 7z
  [cliphist]=cliphist [wtype]=wtype [cava]=cava [app2unit]=app2unit-git [7z]=7zip
  # optional: display settings (wlr-output-management)
  [wlr-randr]=wlr-randr
  # optional: wallpapers + accent colour, Python helpers
  [wallr]=wallr-bin [matugen]=matugen [uv]=uv
  # optional: VPN card (sing-box = TUN engine, Xray = its gRPC / XHTTP
  # nodes), its speed test
  [sing-box]=sing-box [xray]=xray-bin [speedtest-cli]=speedtest-cli
)
missing=()
for t in "${!PKG[@]}"; do have "$t" || missing+=("${PKG[$t]}"); done
# Pillow: lock-screen dissolve (scripts/lock/diff.py), caret calibration,
# wallpaper duplicates — all run on the system python3.
python3 -c "import PIL" 2>/dev/null || missing+=(python-pillow)
# OCR language data (capture AI mode): English at least.
if have tesseract && ! tesseract --list-langs 2>/dev/null | grep -qx eng; then
  missing+=(tesseract-data-eng)
fi
if (( ${#missing[@]} )); then
  mapfile -t missing < <(printf '%s\n' "${missing[@]}" | sort -u)
  echo "   missing: ${missing[*]}"
  echo "   install: paru -S --needed ${missing[*]}   (some are AUR: wallr-bin, app2unit-git, xray-bin)"
else
  echo "   all present"
fi

# --- 0a. Fonts ---
# SF Pro Display = UI text, JetBrainsMono Nerd Font = event glyphs (packages);
# tabler-icons = every icon. Tabler is pinned: 3.31.0 has all codepoints the
# shell uses (newer webfonts moved the filled media icons to another font).
echo "0a. fonts..."
have fc-list || echo "   note: fc-list (fontconfig) not found — font checks skipped"
font_ok() { fc-list ":family=$1" family 2>/dev/null | grep -q .; }
if have fc-list; then
  font_ok "SF Pro Display" || echo "   missing font: SF Pro Display — paru -S otf-san-francisco"
  font_ok "JetBrainsMono Nerd Font" || echo "   missing font: JetBrainsMono Nerd Font — sudo pacman -S ttf-jetbrains-mono-nerd"
  if font_ok "tabler-icons"; then
    echo "   tabler-icons present"
  else
    TABLER_VER=3.31.0
    TABLER_SHA=c63cae0ba30b9b7309a8df66684bee1daf4862b4ce4387dee9a2b22a28ded29c
    TABLER_DIR="$HOME/.local/share/fonts/tabler-icons"
    TABLER_FILE="$TABLER_DIR/tabler-icons.ttf"
    mkdir -p "$TABLER_DIR"
    echo "   downloading tabler-icons $TABLER_VER..."
    if curl -4 -sfL -o "$TABLER_FILE.part" \
        "https://cdn.jsdelivr.net/npm/@tabler/icons-webfont@$TABLER_VER/dist/fonts/tabler-icons.ttf" \
      && echo "$TABLER_SHA  $TABLER_FILE.part" | sha256sum -c --quiet 2>/dev/null; then
      mv "$TABLER_FILE.part" "$TABLER_FILE"
      fc-cache -f "$TABLER_DIR" >/dev/null 2>&1
      echo "   tabler-icons installed: $TABLER_FILE"
    else
      rm -f "$TABLER_FILE.part"
      echo "   error: tabler-icons download failed or checksum mismatch — re-run" >&2
    fi
  fi
fi

# --- 0b. Config ---
# config.json is git-ignored: the shell writes it with every default on its
# first start. Sections that edit it need that full file — a config group
# (property var) is replaced WHOLE by what the file holds, so a partial file
# would drop every other key of the group.
[[ -f "$CONFIG" ]] || echo "0b. config.json not created yet — start the shell once (qs -c flicker), then re-run ./install.sh"

# --- 1. Refine model (Gemma 4 E2B Q4_0, ~2.7 GB, public repo, no auth) ---
# Dictation's LLM cleanup; needs llama-server, skipped without it.
if ! have llama-server; then
  echo "1-2. llama-server not found — skipping dictation Refine (paru -S llama.cpp)"
else
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
if [[ ! -f "$CONFIG" ]]; then
  echo "2. skipped: no config.json yet (see 0b)"
else
echo "2. enabling Refine in config.json..."
CONFIG="$CONFIG" python3 - <<'EOF'
import json
import os
p = os.environ["CONFIG"]
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
fi # config.json
fi # llama-server

# --- 3. Wallpapers (launcher carousel, wallr backend) ---
echo "3. wallpapers..."
# Tools (checked in 0): wallr = the wallpaper daemon; ffmpeg = thumbnails;
# magick = fill-blur composites; matugen = accent colour; uv = the search
# server's Python env; Pillow = duplicate finder; gio = trash.

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

# 3b. Folder and autostart hints (nothing is changed here).
[[ -d "$HOME/Pictures/Wallpapers" ]] || echo "   note: ~/Pictures/Wallpapers does not exist (launcher.wallpapers.dirs)"
for f in "$HOME/.config/driftwm/config.toml" "$HOME/.config/niri/config.kdl"; do
  [[ -f "$f" ]] || continue
  if ! grep -rqs "wallr daemon" "$f" "$(dirname "$f")/modules"; then
    echo "   note: $f does not autostart \"wallr daemon\" (wallpapers need the daemon running)"
  fi
done

# --- 4. Python helper envs into uv's cache ---
# The shell starts every uv script `uv run --offline` first (an online start
# re-resolves deps: ~55 s instead of ~2 s). Transcription (whisperx + torch,
# several GB) is left to its first use.
echo "4. python helpers..."
if have uv; then
  for s in wallpapers/clip.py shazam/recognize.py capture/regions.py; do
    if RUST_LOG=warn uv sync --quiet --script "$FLICKER_DIR/scripts/$s"; then
      echo "   $s env ready"
    else
      echo "   warning: could not prepare the $s env (it is retried online on first use)"
    fi
  done
  # Dictation's websocket client (stream-nemotron.sh looks for this venv).
  WS_VENV="$HOME/.local/share/flicker-ws"
  if "$WS_VENV/bin/python" -c "import websockets" 2>/dev/null; then
    echo "   dictation venv ready"
  elif RUST_LOG=warn uv venv --quiet "$WS_VENV" && RUST_LOG=warn uv pip install --quiet --python "$WS_VENV/bin/python" websockets; then
    echo "   dictation venv created: $WS_VENV"
  else
    echo "   warning: could not create $WS_VENV"
  fi
fi
if [[ ! -x "$HOME/.local/bin/nemo-speech" ]]; then
  echo "   note: no nemo-speech — dictation stays on the test stub (dictation.streamCommand);"
  echo "         see scripts/dictation/nemo-speech.service for the real backend"
fi

# --- 5. Trackpad haptics + Touch Bar tabs (optional, udev rules = root) ---
echo "5. haptics / touch bar..."
haptic_found=0
for b in "$FLICKER_DIR"/scripts/haptics/backends/*/; do
  name=$(basename "$b")
  [[ "$name" == _* ]] && continue
  "$b/backend" probe >/dev/null 2>&1; code=$?
  case $code in
    0) echo "   $name: usable"; haptic_found=1 ;;
    2) # Rule file name from the rules' own "# Install:" line.
       rule=$(grep -oE '/etc/udev/rules\.d/[^ ]+\.rules' "$b/udev.rules" | head -1)
       echo "   $name: hardware found, no access — run:"
       echo "     sudo install -m644 ${b}udev.rules ${rule:-/etc/udev/rules.d/70-flicker-$name.rules}"
       echo "     sudo udevadm control --reload && sudo udevadm trigger"
       haptic_found=1 ;;
  esac
done
(( haptic_found )) || echo "   no haptic trackpad found (fine)"

# Touch Bar press tabs (Macs with tiny-dfr only, udev rule = root).
tb_dev=$(grep -lx "Dynamic Function Row Virtual Input Device" /sys/class/input/event*/device/name 2>/dev/null | head -1 | cut -d/ -f5)
if [[ -n "$tb_dev" && ! -r "/dev/input/$tb_dev" ]]; then
  echo "   touch bar: tiny-dfr found, no access — run:"
  echo "     sudo install -m644 $FLICKER_DIR/scripts/touchbar/udev.rules /etc/udev/rules.d/70-flicker-touchbar.rules"
  echo "     sudo udevadm control --reload && sudo udevadm trigger -s input"
elif [[ -n "$tb_dev" ]]; then
  echo "   touch bar: usable"
fi

# --- 6. VPN card (optional, polkit rule = root) ---
# Start / stop without a password prompt: a polkit rule limited to the
# sing-box and xray units (scripts/vpn/vpn.sh setup asks for it once).
# The rules directory is root-only, so this cannot tell whether it is in.
echo "6. vpn..."
if have sing-box; then
  echo "   sing-box present; for start / stop without a password, once:"
  echo "     $FLICKER_DIR/scripts/vpn/vpn.sh setup"
  have xray || echo "   note: no xray — gRPC / XHTTP nodes stay on sing-box (gRPC usually fails)"
else
  echo "   no sing-box (VPN card reads \"Not installed\", fine)"
fi

echo "done. start the shell: qs -c flicker"
