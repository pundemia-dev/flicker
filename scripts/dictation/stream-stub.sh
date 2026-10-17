#!/usr/bin/env bash
# stream-stub.sh — test streaming backend for Flicker dictation (no models).
#
# Contract (identical for the real Nemotron backend, see stream-nemotron.sh):
#   stdout: JSON lines, one object per line:
#     {"type":"ready"}                        model loaded (stub: instant)
#     {"type":"partial","text":"...","seq":N}    live hypothesis (rewritable)
#     {"type":"final","text":"...","lang":"ru"}  VAD-fixed segment (committed)
#     {"type":"error","message":"..."}           fatal backend error
#   signals: on SIGINT/SIGTERM flush one final line for the buffered draft,
#     then exit 0 — mirroring `pw-record` + SIGINT finalizing the wav.
#
# Env: DICT_LANG (auto|ru|en — stub picks the phrase set), DICT_CHUNK_MS
#   (delay between partials; the real backend uses it as the ASR chunk),
#   DICT_SESSION_FILE (JSONL session tail watched by the shell; when set,
#   lines go both there and to stdout).
set -u

LANG_SET="${DICT_LANG:-auto}"
STEP_MS="${DICT_CHUNK_MS:-500}"
SESSION="${DICT_SESSION_FILE:-}"
[[ "$STEP_MS" =~ ^[0-9]+$ ]] || STEP_MS=500
STEP_S="$(awk -v m="$STEP_MS" 'BEGIN { printf "%.3f", (m < 150 ? 150 : m) / 1000 }')"

emit() {
  printf '%s\n' "$1"
  if [[ -n "$SESSION" ]]; then printf '%s\n' "$1" >> "$SESSION"; fi
}

# Pre-create the session tail so the shell's FileView never sees it missing.
if [[ -n "$SESSION" ]]; then : >> "$SESSION"; fi

# Model is instant here: tell the shell to flip from "switching" to live.
emit '{"type":"ready"}'

if [[ "$LANG_SET" == "en" ]]; then
  P1="Hello"; P2="Hello, this is"; P3="Hello, this is a dictation test"
  FINAL="Hello, this is a dictation test."; OUT_LANG="en"
else
  P1="Привет"; P2="Привет, это"; P3="Привет, это тест диктовки"
  FINAL="Привет, это тест диктовки."; OUT_LANG="ru"
fi

emitted=0
emit_final() {
  if [[ "$emitted" -eq 0 ]]; then
    emitted=1
    emit "{\"type\":\"final\",\"text\":\"$FINAL\",\"lang\":\"$OUT_LANG\"}"
  fi
}
trap 'emit_final; exit 0' INT TERM

emit "{\"type\":\"partial\",\"text\":\"$P1\",\"seq\":1}"; sleep "$STEP_S"
emit "{\"type\":\"partial\",\"text\":\"$P2\",\"seq\":2}"; sleep "$STEP_S"
emit "{\"type\":\"partial\",\"text\":\"$P3\",\"seq\":3}"; sleep "$STEP_S"

# Stay alive until the shell sends SIGINT (stop) or SIGKILL (cancel):
# stop -> trap flushes the final line; cancel -> killed, typer erases.
while true; do sleep 0.2; done
