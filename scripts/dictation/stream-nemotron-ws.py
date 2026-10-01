#!/usr/bin/env python3
"""stream-nemotron-ws.py — mic PCM into NeMo-Speech.cpp realtime WS.

Spawns pw-record itself (single direct child of the shell, so SIGINT/SIGTERM
land here deterministically), streams raw s16le 16k mono to the WS and emits
pillShell dictation JSONL (partial/final/error) to DICT_SESSION_FILE.

Transport is the session FILE (the shell tails it); stdout is deliberately
NOT used — nothing drains the process stdout pipe, so printing every
partial there would block once the pipe buffer fills.

Env: NEMO_WS_URL (default ws://127.0.0.1:8090/v1/audio/transcriptions/realtime),
  DICT_LANG (auto|ru|en -> auto|ru-RU|en-US), DICT_SESSION_FILE (append lines),
  DICT_CHUNK_BYTES (mic read frame, default 2048 = ~64ms @16k mono s16),
  DICT_TRAIL_SILENCE_BYTES (default 16000 = 0.5s zeros to flush the model),
  PW_CMD (mic command override, default pw-record).

Emitted JSONL lines: {"type":"ready"} once the server acks session.update
(model loaded), then partial/final/error as the session runs.

Exit codes: 0 = clean Stop (SIGINT: tail flushed); 1 = abnormal end (WS or
mic died on its own — error line emitted first, so the shell shows why
instead of just going quiet).

Mic reads use small fixed frames via os.read (returns what arrived, never
waits to fill): send size does NOT affect the model's server-side chunking,
so big reads would only add latency to partials. DICT_CHUNK_MS is ignored
(it paces only the test stub).

Protocol notes (verified against nemo-speech 0.1.0):
  delta events carry APPEND increments; hypothesis = concat of deltas since
  the last completed. completed carries the authoritative "transcript".
  Partials are emitted only when the hypothesis CHANGES (the server also
  sends empty keepalive deltas). On stop (SIGINT): terminate the mic FIRST
  (nothing recorded after Stop may leak into the text), drain the pipe to
  EOF, feed trailing silence, commit, wait for the trailing completed
  (bounded), close the WS and exit 0.
"""
import asyncio
import json
import os
import signal
import subprocess
import sys

try:
    import websockets
except ImportError:
    _msg = {"type": "error", "message":
        "stream backend: python 'websockets' package missing "
        "(need the pillshell-ws venv python)"}
    _line = json.dumps(_msg, ensure_ascii=False)
    print(_line, file=sys.stderr, flush=True)
    _sess = os.environ.get("DICT_SESSION_FILE", "")
    if _sess:
        try:
            _fd = os.open(_sess, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
            with os.fdopen(_fd, "a") as _f:
                _f.write(_line + "\n")
        except Exception:
            pass
    sys.exit(1)

WS_URL = os.environ.get(
    "NEMO_WS_URL", "ws://127.0.0.1:8090/v1/audio/transcriptions/realtime")
LANG = {"ru": "ru-RU", "en": "en-US"}.get(
    os.environ.get("DICT_LANG", "auto"), "auto")
SESSION = os.environ.get("DICT_SESSION_FILE", "")
# Mic read frame: small and fixed. os.read returns what already arrived
# instead of waiting to fill the buffer, so partial latency stays at tens
# of ms. (A big CHUNK derived from chunkMs blocked a full 800ms per read.)
FRAME = max(512, min(8192, int(os.environ.get("DICT_CHUNK_BYTES", "2048"))))
PW_CMD = os.environ.get(
    "PW_CMD", "pw-record --rate 16000 --channels 1 --format s16 -")
# Trailing silence to flush a cache-aware streaming model before commit
# (0.5s of 16k s16 mono zeros); tune experimentally per backend.
TRAIL_SILENCE_BYTES = int(os.environ.get("DICT_TRAIL_SILENCE_BYTES", "16000"))
# Upper bound for the post-terminate pipe drain (~4s of audio); the loop
# normally ends at EOF much earlier.
MAX_DRAIN_BYTES = 131072
# Ceiling for the trailing completed after commit; then close anyway.
TRAIL_COMPLETED_TIMEOUT = float(
    os.environ.get("DICT_TRAIL_COMPLETED_TIMEOUT", "2.5"))


def emit(obj):
    # File only (see module docstring: stdout is never drained).
    line = json.dumps(obj, ensure_ascii=False)
    if SESSION:
        try:
            fd = os.open(SESSION, os.O_WRONLY | os.O_CREAT | os.O_APPEND,
                         0o600)
            with os.fdopen(fd, "a") as f:
                f.write(line + "\n")
        except Exception as e:
            print(f"session write failed: {e}", file=sys.stderr, flush=True)


def emit_error(message):
    emit({"type": "error", "message": message})
    try:
        print(json.dumps({"type": "error", "message": message},
                         ensure_ascii=False),
              file=sys.stderr, flush=True)
    except Exception:
        pass


mic = None


def _spawn_mic():
    global mic
    try:
        mic = subprocess.Popen(
            PW_CMD.split(), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    except Exception as e:
        emit_error(f"stream backend: cannot start mic ({e})")
        sys.exit(1)


async def main():
    # Pre-create the session tail so the shell's FileView never sees it
    # missing (a missed creation = all text arriving as one chunk on exit).
    # Mode 0600: the file holds verbatim dictation.
    if SESSION:
        try:
            fd = os.open(SESSION, os.O_WRONLY | os.O_CREAT | os.O_TRUNC,
                         0o600)
            os.close(fd)
        except Exception as e:
            print(f"session create failed: {e}", file=sys.stderr, flush=True)
    hyp = ""
    last_emitted = None
    last_completed = None
    deltas_since_completed = 0

    def emit_final(text, lang):
        nonlocal last_completed, deltas_since_completed
        t = (text or "").strip()
        # Echo gate: the server may finalize twice (endpointing + commit
        # echo) with NO new deltas in between. A genuine user repeat always
        # brings fresh non-empty deltas first — so gate on those, never on
        # a bare time window (which would eat fast "Да. / Да.").
        if t and (t != last_completed or deltas_since_completed > 0):
            emit({"type": "final", "text": t, "lang": lang})
            last_completed = t
        deltas_since_completed = 0
    try:
        ws = await websockets.connect(WS_URL, max_size=1 << 26,
                                      ping_interval=None)
    except Exception as e:
        emit_error(f"nemo-speech WS unreachable ({WS_URL}): {e}. "
                   "Is 'nemo-speech serve' running?")
        return 1
    _spawn_mic()
    loop = asyncio.get_running_loop()
    stop = asyncio.Event()

    try:
        loop.add_signal_handler(signal.SIGINT, stop.set)
        loop.add_signal_handler(signal.SIGTERM, stop.set)
    except (NotImplementedError, RuntimeError):
        # Fallback (non-Unix loop): plain handlers; the sender still wakes
        # every mic chunk (~160ms) and notices the flag.
        def _ask_stop(*a):
            loop.call_soon_threadsafe(stop.set)
        signal.signal(signal.SIGINT, _ask_stop)
        signal.signal(signal.SIGTERM, _ask_stop)

    async with ws:
        await ws.send(json.dumps({"type": "session.update",
            "session": {"sample_rate": 16000, "language": LANG,
                        "word_timestamps": False}}))

        # Set after the commit goes out; the receiver signals trailing_done
        # on the first completed past that point. Waiting for the event
        # (instead of the receiver task, which ends only when the server
        # closes the session) bounds Stop latency to ~seconds, not the full
        # recv timeout. The session ack is watched by the receiver in
        # parallel — the sender starts streaming immediately instead of
        # idling the mic for up to 5s on a silent server.
        commit_sent = asyncio.Event()
        trailing_done = asyncio.Event()
        acked = False

        async def sender():
            mic_fd = mic.stdout.fileno()
            while not stop.is_set():
                chunk = await loop.run_in_executor(
                    None, os.read, mic_fd, FRAME)
                if not chunk:
                    break
                try:
                    await ws.send(chunk)
                except Exception:
                    break
            # Stop (or mic death): terminate FIRST so nothing spoken after
            # Stop leaks into the transcript, then drain what pw-record had
            # already buffered. The process is dead by drain time, so EOF
            # is guaranteed and plain blocking reads are safe and bounded.
            if mic.poll() is None:
                try:
                    mic.terminate()
                except Exception:
                    pass
            try:
                await asyncio.wait_for(loop.run_in_executor(
                    None, mic.wait), timeout=2.0)
            except Exception:
                try:
                    mic.kill()
                except Exception:
                    pass
                try:
                    await loop.run_in_executor(None, mic.wait)
                except Exception:
                    pass
            try:
                drained = 0
                while drained < MAX_DRAIN_BYTES:
                    chunk = await loop.run_in_executor(
                        None, os.read, mic_fd, FRAME)
                    if not chunk:
                        break
                    drained += len(chunk)
                    try:
                        await ws.send(chunk)
                    except Exception:
                        break
            except Exception:
                pass
            # Trailing silence so a cache-aware model flushes final tokens.
            if TRAIL_SILENCE_BYTES > 0:
                try:
                    silence = b"\x00" * TRAIL_SILENCE_BYTES
                    for i in range(0, len(silence), FRAME):
                        await ws.send(silence[i:i + FRAME])
                except Exception:
                    pass
            try:
                await ws.send(json.dumps(
                    {"type": "input_audio_buffer.commit"}))
                commit_sent.set()
            except Exception:
                commit_sent.set()
                return
            try:
                await asyncio.wait_for(trailing_done.wait(),
                                       timeout=TRAIL_COMPLETED_TIMEOUT)
            except (TimeoutError, asyncio.TimeoutError):
                pass
            try:
                await ws.close()
            except Exception:
                pass

        async def receiver():
            nonlocal hyp, last_emitted, deltas_since_completed, acked
            try:
                async for msg in ws:
                    if not isinstance(msg, str):
                        continue
                    try:
                        m = json.loads(msg)
                    except Exception:
                        continue
                    t = m.get("type", "")
                    if t.endswith(".updated"):
                        # Session ack (model loaded) — watched in parallel
                        # with streaming, never blocking the mic.
                        if not acked:
                            acked = True
                            emit({"type": "ready"})
                        continue
                    if t.endswith(".delta"):
                        d = m.get("delta", "") or ""
                        # Empty keepalive deltas carry no text: ignore them
                        # so they neither spam partials nor fake "new speech"
                        # for the echo gate.
                        if not d:
                            continue
                        hyp += d
                        deltas_since_completed += 1
                        if hyp != last_emitted:
                            last_emitted = hyp
                            emit({"type": "partial", "text": hyp})
                    elif t.endswith(".completed"):
                        text = (m.get("transcript", "") or "").strip()
                        lang = m.get("language", LANG)
                        if text:
                            emit_final(text, lang)
                        else:
                            # Empty completion with a stale hypothesis on
                            # screen: send an empty final so the shell
                            # clears the draft instead of leaving it stuck.
                            emit({"type": "final", "text": "",
                                  "lang": lang})
                        hyp = ""
                        last_emitted = None
                        if commit_sent.is_set() \
                                and not trailing_done.is_set():
                            trailing_done.set()
                    elif t == "error":
                        if commit_sent.is_set():
                            # Post-commit server notice (e.g. commit on an
                            # already-empty buffer after trailing silence):
                            # logged, never failed — every Stop would error
                            # otherwise.
                            print(f"post-commit server notice ignored: "
                                  f"{m.get('message', m.get('error', ''))}",
                                  file=sys.stderr, flush=True)
                        else:
                            emit_error(m.get("message", m.get("error",
                                                             "server error")))
            except Exception:
                pass

        send_task = asyncio.create_task(sender())
        recv_task = asyncio.create_task(receiver())
        await send_task
        if not stop.is_set():
            # Abnormal end (WS dropped or mic EOF on its own): the tail is
            # flushed first so speech survives on screen, then an error line
            # goes out and we exit 1 — the shell must show WHY dictation
            # stopped instead of just going quiet.
            if hyp.strip():
                emit_final(hyp.strip(), LANG)
            try:
                await asyncio.wait_for(recv_task, timeout=1.0)
            except (TimeoutError, asyncio.TimeoutError):
                recv_task.cancel()
            emit_error("connection or mic lost")
            return 1
        # Sender closed the WS after the trailing completed (or its
        # ceiling), so the receiver drains on its own; only bound the wait.
        try:
            await asyncio.wait_for(recv_task, timeout=2.0)
        except (TimeoutError, asyncio.TimeoutError):
            recv_task.cancel()
        if hyp.strip():
            emit_final(hyp.strip(), LANG)
    return 0


try:
    sys.exit(asyncio.run(main()))
except KeyboardInterrupt:
    # SIGINT before the loop installed its handlers (connect/mic spawn):
    # nothing was streamed yet, so there is no tail to flush.
    sys.exit(0)
