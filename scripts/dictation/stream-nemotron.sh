#!/usr/bin/env bash
# stream-nemotron.sh — live backend for pillShell dictation (Nemotron 3.5).
#
# Single process (python execs below): SIGINT/SIGTERM land in
# stream-nemotron-ws.py, which kills its own pw-record child, commits the
# server buffer, flushes the trailing final and exits 0.
#
# Requires: `nemo-speech serve` running (unit: ./nemo-speech.service,
# enable via symlink into ~/.config/systemd/user + systemctl --user enable --now).
# Env: NEMO_WS_URL (default ws://127.0.0.1:8090/v1/audio/transcriptions/realtime),
#   DICT_LANG (auto|ru|en), DICT_CHUNK_BYTES (mic read frame for the python,
#   default 2048; DICT_CHUNK_MS paces only the test stub and is ignored here),
#   DICT_SESSION_FILE (set by Dictation), PW_CMD (mic override),
#   NEMO_CLIENT_CMD (full override).
set -u
umask 077

# Resolve the sibling python relative to this script, not a hardcoded home.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_PY="$SCRIPT_DIR/stream-nemotron-ws.py"
# Interpreter with the `websockets` package: dedicated venv first, then system.
WS_VENV_PY="$HOME/.local/share/pillshell-ws/bin/python"
if [[ -x "$WS_VENV_PY" ]] && "$WS_VENV_PY" -c "import websockets" 2>/dev/null; then
  WS_PY_BIN="$WS_VENV_PY"
elif command -v python3 >/dev/null && python3 -c "import websockets" 2>/dev/null; then
  WS_PY_BIN="python3"
else
  _err='{"type":"error","message":"stream backend: no python with websockets (create pillshell-ws venv)"}'
  printf '%s\n' "$_err" >&2
  if [[ -n "${DICT_SESSION_FILE:-}" ]]; then printf '%s\n' "$_err" >> "$DICT_SESSION_FILE"; fi
  exit 1
fi

# Backend errors must reach the shell: DictationStream tails
# DICT_SESSION_FILE and keeps the stderr tail. stdout is NOT used (nothing
# drains that pipe — printing there would block on a full buffer).
err() {
  printf '%s\n' "$1" >&2
  if [[ -n "${DICT_SESSION_FILE:-}" ]]; then printf '%s\n' "$1" >> "${DICT_SESSION_FILE}"; fi
}

# Pre-create the session tail so the shell's FileView never sees it missing.
if [[ -n "${DICT_SESSION_FILE:-}" ]]; then : >> "$DICT_SESSION_FILE"; fi

if [[ -n "${NEMO_CLIENT_CMD:-}" ]]; then
  # shellcheck disable=SC2086
  exec $NEMO_CLIENT_CMD
fi

command -v pw-record >/dev/null 2>&1 || {
  err '{"type":"error","message":"stream backend: pw-record not found"}'
  exit 1
}
command -v curl >/dev/null 2>&1 || {
  err '{"type":"error","message":"stream backend: curl not found"}'
  exit 1
}
[[ -f "$WS_PY" ]] || {
  err "{\"type\":\"error\",\"message\":\"stream backend: $WS_PY missing\"}"
  exit 1
}

# Fail fast with a clear error instead of a silent session. Honor NEMO_WS_URL
# instead of a hardcoded port: derive scheme/host:port + /ready from it
# (ws→http, wss→https).
NEMO_WS_URL="${NEMO_WS_URL:-ws://127.0.0.1:8090/v1/audio/transcriptions/realtime}"
_READY_SCHEME="http"
case "$NEMO_WS_URL" in wss://*) _READY_SCHEME="https";; esac
_READY="$(printf '%s' "$NEMO_WS_URL" | sed -E 's#^wss?://##; s#/.*$##')"
_READY_HOST="${_READY%%:*}"
_READY_PORT="${_READY##*:}"
[[ "$_READY_PORT" == "$_READY" ]] && _READY_PORT=80
if ! curl -fsS --max-time 3 "${_READY_SCHEME}://${_READY_HOST}:${_READY_PORT}/ready" >/dev/null 2>&1; then
  err "{\"type\":\"error\",\"message\":\"nemo-speech serve not reachable at ${_READY_HOST}:${_READY_PORT} (systemctl --user start nemo-speech)\"}"
  exit 1
fi

export NEMO_WS_URL
exec "$WS_PY_BIN" "$WS_PY"
