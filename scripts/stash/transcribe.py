#!/usr/bin/env -S uv run --script --quiet
# /// script
# requires-python = ">=3.10,<3.14"
# dependencies = ["whisperx>=3.8"]
#
# [tool.uv.sources]
# torch = { index = "pytorch-cpu" }
# torchaudio = { index = "pytorch-cpu" }
# torchvision = { index = "pytorch-cpu" }
#
# [[tool.uv.index]]
# name = "pytorch-cpu"
# url = "https://download.pytorch.org/whl/cpu"
# explicit = true
# ///
"""Speech-to-text of an existing audio / video file (WhisperX) for
services/Transcribe.qml (stash tray button).

Usage: transcribe.py --file F --out JSON [--model M] [--language auto|xx]
                     [--device cpu|cuda] [--compute-type T] [--batch-size N]
                     [--threads N] [--vad pyannote|silero] [--align 0|1]
                     [--diarize 0|1] [--hf-token T] [--min-speakers N]
                     [--max-speakers N] [--models-dir D]

Prints JSON lines on stdout:
  {"state": "loading"}                          model / audio loading
  {"state": "transcribing"|"aligning"|"diarizing", "progress": 0..1}
                                                progress = whole run
  {"state": "done", "out", "language"}
  {"state": "error", "message"}
Result (written atomically to --out):
  {version, source, mtime, size, model, language, diarized, duration,
   segments: [{start, end, text, speaker?}]}
torch comes from the PyTorch CPU index (the default PyPI wheel drags in
~3 GB of CUDA libraries). Every library print goes to stderr: fd 1 is
re-pointed there, the protocol writes to a private dup of it.
"""

import argparse
import json
import os
import re
import sys

_proto = os.fdopen(os.dup(1), "w", buffering=1)
os.dup2(2, 1)


def emit(obj):
    _proto.write(json.dumps(obj, ensure_ascii=False) + "\n")
    _proto.flush()


class ProgressTap:
    """sys.stdout stand-in: forwards to stderr, turns WhisperX's
    "Progress: 42.00%..." prints into protocol progress of the stage."""

    pat = re.compile(r"Progress:\s*([\d.]+)%")

    def __init__(self):
        self.stage = None
        self.base = 0.0
        self.span = 0.0
        self.last = -1.0

    def write(self, s):
        sys.__stderr__.write(s)
        m = self.pat.search(s)
        if m and self.stage:
            p = self.base + self.span * min(1.0, float(m.group(1)) / 100)
            if p - self.last >= 0.005:
                self.last = p
                emit({"state": self.stage, "progress": round(p, 4)})
        return len(s)

    def flush(self):
        sys.__stderr__.flush()

    def enter(self, stage, base, span):
        self.stage, self.base, self.span = stage, base, span
        emit({"state": stage, "progress": round(base, 4)})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--model", default="large-v3-turbo")
    ap.add_argument("--language", default="auto")
    ap.add_argument("--device", default="cpu")
    ap.add_argument("--compute-type", default="int8")
    ap.add_argument("--batch-size", type=int, default=8)
    ap.add_argument("--threads", type=int, default=0)
    ap.add_argument("--vad", default="pyannote")
    ap.add_argument("--align", type=int, default=1)
    ap.add_argument("--diarize", type=int, default=0)
    ap.add_argument("--hf-token", default="")
    ap.add_argument("--min-speakers", type=int, default=0)
    ap.add_argument("--max-speakers", type=int, default=0)
    ap.add_argument("--models-dir", default="")
    a = ap.parse_args()

    tap = ProgressTap()
    sys.stdout = tap
    emit({"state": "loading"})

    import torch
    import whisperx

    if a.threads > 0:
        torch.set_num_threads(a.threads)
    lang = None if a.language in ("", "auto") else a.language
    token = a.hf_token or None

    # Stage weights of the whole run's progress.
    w = {"transcribing": 0.75, "aligning": 0.1 if a.align else 0, "diarizing": 0.15 if a.diarize else 0}
    total = sum(w.values())
    w = {k: v / total for k, v in w.items()}

    audio = whisperx.load_audio(a.file)
    duration = len(audio) / 16000
    model = whisperx.load_model(
        a.model, a.device, compute_type=a.compute_type, language=lang,
        vad_method=a.vad, threads=a.threads if a.threads > 0 else 4,
        download_root=a.models_dir or None,
    )
    tap.enter("transcribing", 0, w["transcribing"])
    result = model.transcribe(audio, batch_size=a.batch_size, language=lang,
                              print_progress=True, combined_progress=False)
    language = result.get("language") or lang or ""
    del model

    pos = w["transcribing"]
    if a.align and result["segments"]:
        tap.enter("aligning", pos, w["aligning"])
        try:
            ma, meta = whisperx.load_align_model(language_code=language, device=a.device)
            result = whisperx.align(result["segments"], ma, meta, audio, a.device,
                                    return_char_alignments=False, print_progress=True)
            del ma
        except Exception as e:  # no align model for this language: keep ASR timings
            print(f"align skipped: {e}", file=sys.stderr)
        pos += w["aligning"]

    diarized = False
    if a.diarize and result["segments"]:
        tap.enter("diarizing", pos, w["diarizing"])
        from whisperx.diarize import DiarizationPipeline
        try:
            pipe = DiarizationPipeline(token=token, device=a.device)
        except TypeError:
            pipe = DiarizationPipeline(use_auth_token=token, device=a.device)
        kw = {}
        if a.min_speakers > 0:
            kw["min_speakers"] = a.min_speakers
        if a.max_speakers > 0:
            kw["max_speakers"] = a.max_speakers
        result = whisperx.assign_word_speakers(pipe(audio, **kw), result)
        diarized = True

    segs = []
    for s in result["segments"]:
        text = (s.get("text") or "").strip()
        if not text:
            continue
        seg = {"start": round(float(s.get("start", 0)), 3), "end": round(float(s.get("end", 0)), 3), "text": text}
        if diarized and s.get("speaker"):
            seg["speaker"] = s["speaker"]
        segs.append(seg)

    st = os.stat(a.file)
    doc = {
        "version": 1, "source": os.path.abspath(a.file), "mtime": int(st.st_mtime), "size": st.st_size,
        "model": a.model, "language": language, "diarized": diarized,
        "duration": round(duration, 2), "segments": segs,
    }
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    tmp = a.out + ".part"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False)
    os.replace(tmp, a.out)
    emit({"state": "done", "out": a.out, "language": language})


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
    except Exception as e:
        emit({"state": "error", "message": f"{type(e).__name__}: {e}"})
        sys.exit(1)
