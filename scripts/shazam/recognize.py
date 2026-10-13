#!/usr/bin/env -S uv run --script --quiet
# /// script
# requires-python = ">=3.12,<3.14"
# dependencies = ["shazamio", "audioop-lts"]
# ///
"""Music recognition (Shazam) for services/Shazam.qml.

Usage: recognize.py --source auto|monitor|mic --step S --max S --cache DIR
                    [--probe S --silence N]

Records the default output monitor (what the computer plays) or the default
microphone (auto: the monitor, or the mic when its first --probe seconds
peak below --silence) with parecord (raw s16le 16 kHz mono on a pipe) and asks Shazam
every --step seconds with the last up-to-12 s of audio, until a match or
--max seconds. Prints JSON lines on stdout:
  {"state": "listening", "source"}             recording (again on a switch)
  {"state": "found", "title", "artist", "url", "cover", "album", "year"}
  {"state": "none"}                            nothing matched within --max
  {"state": "error", "message"}
The cover is downloaded to <cache>/<track key>.jpg ("" when it failed).
Python < 3.14: shazamio-core has no 3.14 wheels (source build = minutes);
audioop-lts: pydub (a shazamio import) needs audioop, gone in 3.13.
Stream names `pillshell_rec_shazam` (monitor, ignored by the mic indicator)
/ `pillshell_shazam_mic` (mic, shows the privacy dot).
"""

import argparse
import asyncio
import io
import json
import os
import subprocess
import sys
import urllib.request
import wave

RATE = 16000
BYTES_PER_SEC = RATE * 2
WINDOW_SEC = 12


def emit(obj):
    print(json.dumps(obj, ensure_ascii=False), flush=True)


def wav_bytes(pcm):
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm)
    return buf.getvalue()


def fetch_cover(url, cache, key):
    if not url:
        return ""
    try:
        os.makedirs(cache, exist_ok=True)
        path = os.path.join(cache, f"{key}.jpg")
        if not os.path.exists(path):
            with urllib.request.urlopen(url, timeout=10) as r, open(path + ".part", "wb") as f:
                f.write(r.read())
            os.replace(path + ".part", path)
        return path
    except Exception:
        return ""


def metadata(track, title):
    for section in track.get("sections") or []:
        for m in section.get("metadata") or []:
            if m.get("title") == title:
                return m.get("text") or ""
    return ""


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", default="auto", choices=["auto", "monitor", "mic"])
    ap.add_argument("--step", type=float, default=4)
    ap.add_argument("--max", type=float, default=15)
    ap.add_argument("--probe", type=float, default=1.0, help="auto: seconds of output checked")
    ap.add_argument("--silence", type=int, default=300, help="auto: peak (of 32767) below = silent")
    ap.add_argument("--device", default="", help="PulseAudio source (tests)")
    ap.add_argument("--cache", default=os.path.expanduser("~/.cache/pillShell/shazam"))
    a = ap.parse_args()

    from shazamio import Shazam

    state = {"proc": None, "pcm": bytearray(), "dead": False}

    async def record(source):
        device = a.device or ("@DEFAULT_MONITOR@" if source == "monitor" else "@DEFAULT_SOURCE@")
        name = "pillshell_rec_shazam" if source == "monitor" else "pillshell_shazam_mic"
        proc = await asyncio.create_subprocess_exec(
            "parecord", "--raw", "--format=s16le", f"--rate={RATE}", "--channels=1",
            "--latency-msec=50", f"--device={device}", f"--client-name={name}",
            f"--stream-name={name}",
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        state.update(proc=proc, pcm=bytearray(), dead=False)
        emit({"state": "listening", "source": source})

        # Reads all the time, also while Shazam answers (a full pipe would
        # stall parecord and lose that audio).
        async def pump():
            while True:
                chunk = await proc.stdout.read(4096)
                if not chunk:
                    state["dead"] = True
                    return
                state["pcm"] += chunk
        return asyncio.create_task(pump())

    async def stop():
        proc = state["proc"]
        if proc and proc.returncode is None:
            proc.terminate()
            await proc.wait()

    def heard():
        return len(state["pcm"]) / BYTES_PER_SEC

    async def wait_until(sec):
        while heard() < sec:
            if state["dead"]:
                return False
            await asyncio.sleep(0.05)
        return True

    source = "monitor" if a.source in ("auto", "monitor") else "mic"
    pump = await record(source)
    shazam = Shazam()
    try:
        # auto: nothing plays on the computer -> listen to the room instead.
        if a.source == "auto" and not a.device:
            if not await wait_until(a.probe):
                emit({"state": "error", "message": "audio capture failed"})
                return
            samples = memoryview(bytes(state["pcm"])).cast("h")
            if max((abs(v) for v in samples), default=0) < a.silence:
                pump.cancel()
                await stop()
                pump = await record("mic")
        next_at = a.step
        while True:
            if not await wait_until(next_at):
                emit({"state": "error", "message": "audio capture failed"})
                return
            window = bytes(state["pcm"][-WINDOW_SEC * BYTES_PER_SEC:])
            try:
                res = await shazam.recognize(wav_bytes(window))
            except Exception as e:
                emit({"state": "error", "message": f"{type(e).__name__}: {e}"})
                return
            track = res.get("track")
            if track:
                await stop()
                images = track.get("images") or {}
                key = track.get("key") or "cover"
                emit({
                    "state": "found",
                    "title": track.get("title") or "",
                    "artist": track.get("subtitle") or "",
                    "url": track.get("url") or "",
                    "album": metadata(track, "Album"),
                    "year": metadata(track, "Released"),
                    "cover": fetch_cover(images.get("coverarthq") or images.get("coverart"), a.cache, key),
                })
                return
            if heard() >= a.max:
                emit({"state": "none"})
                return
            next_at = heard() + a.step
    finally:
        pump.cancel()
        await stop()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        sys.exit(130)
