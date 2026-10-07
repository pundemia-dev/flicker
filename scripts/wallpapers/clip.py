#!/usr/bin/env -S uv run --script --quiet
# /// script
# requires-python = ">=3.11"
# dependencies = ["onnxruntime", "numpy", "pillow", "tokenizers"]
# ///
"""Semantic wallpaper search server (services/WallpaperSemantic).

Model: visheratin/mexma-siglip2 (MIT) — MEXMA multilingual text encoder +
SigLIP 2 So400m image encoder, ONNX (mexma_image_encoder.onnx: pixel_values
1x3x512x512 → 1152; mexma_text_encoder.onnx: input_ids/attention_mask 1x32
→ 1152). Chosen after a comparison (Oct 2026): best multilingual
text→image retrieval (XM3600 R@1 62.5 vs SigLIP 2 B 40.7 / So400m 48.1),
understands Russian queries. Measured on the user's i7-9750H: ~2.8 s per
image with 6 threads (12 is slower; int8 dynamic quantization gave nothing,
the export is already quantized), ~60 ms per query.

Usage: clip.py <modelDir> <storeDir> <threads> <idleSec>
Reads JSON lines on stdin, writes JSON lines on stdout:
  {"cmd": "index", "items": [[key, thumbPath], ...]}
      embeds every key not in the store yet (nice 10, saved every 16),
      → {"event": "progress", "done": n, "total": m} ... {"event": "indexed", "count": n}
  {"cmd": "query", "id": n, "text": "..."}   → {"event": "scores", "id": n, "scores": {key: s}}
  {"cmd": "similar", "id": n, "key": "..."}  → same, by that image's vector
  {"cmd": "forget", "keep": [key, ...]}      drops vectors of vanished files
  {"cmd": "stop"}                            stops a running index after the current image
Vectors are L2-normalised float16 in <storeDir>/vectors.npy + keys.json
(written atomically). The image encoder is loaded only while indexing and
dropped after; the process exits after idleSec without a command.
"""
import json
import os
import queue
import sys
import threading
import time

import numpy as np

model_dir, store_dir = os.path.expanduser(sys.argv[1]), os.path.expanduser(sys.argv[2])
threads, idle_sec = int(sys.argv[3]), float(sys.argv[4])
os.makedirs(store_dir, exist_ok=True)
VEC, KEYS = os.path.join(store_dir, "vectors.npy"), os.path.join(store_dir, "keys.json")
out_lock = threading.Lock()


def emit(obj):
    with out_lock:
        sys.stdout.write(json.dumps(obj) + "\n")
        sys.stdout.flush()


# ---- store ----
keys, vecs = [], np.zeros((0, 1152), np.float16)
try:
    with open(KEYS) as f:
        keys = json.load(f)
    vecs = np.load(VEC)
    if len(keys) != len(vecs):
        keys, vecs = [], np.zeros((0, 1152), np.float16)
except (OSError, ValueError):
    pass
index = {k: i for i, k in enumerate(keys)}
store_lock = threading.Lock()


def save():
    with store_lock:
        np.save(VEC + ".tmp.npy", vecs)
        os.replace(VEC + ".tmp.npy", VEC)
        with open(KEYS + ".tmp", "w") as f:
            json.dump(keys, f)
        os.replace(KEYS + ".tmp", KEYS)


def add(key, v):
    global vecs
    with store_lock:
        if key in index:
            return
        index[key] = len(keys)
        keys.append(key)
        vecs = np.concatenate([vecs, v[None].astype(np.float16)])


# ---- models (lazy) ----
import onnxruntime as ort

sessions = {}


def session(name):
    if name not in sessions:
        so = ort.SessionOptions()
        so.intra_op_num_threads = threads
        sessions[name] = ort.InferenceSession(os.path.join(model_dir, f"mexma_{name}_encoder.onnx"), so,
                                              providers=["CPUExecutionProvider"])
    return sessions[name]


tokenizer = None


def embed_text(text):
    global tokenizer
    if tokenizer is None:
        from tokenizers import Tokenizer
        tokenizer = Tokenizer.from_file(os.path.join(model_dir, "tokenizer.json"))
        tokenizer.enable_truncation(32)
        tokenizer.enable_padding(length=32, pad_id=1, pad_token="<pad>")
    enc = tokenizer.encode(text)
    v = session("text").run(None, {"input_ids": np.array([enc.ids], np.int64),
                                   "attention_mask": np.array([enc.attention_mask], np.int64)})[0][0]
    return v / (np.linalg.norm(v) or 1)


def embed_image(path):
    from PIL import Image
    with Image.open(path) as im:
        im = im.convert("RGB").resize((512, 512), Image.Resampling.BILINEAR)
        a = ((np.asarray(im, np.float32) / 255.0 - 0.5) / 0.5).transpose(2, 0, 1)[None]
    v = session("image").run(None, {"pixel_values": a})[0][0]
    return v / (np.linalg.norm(v) or 1)


def scores_for(v):
    with store_lock:
        if not keys:
            return {}
        s = vecs.astype(np.float32) @ v.astype(np.float32)
        return {k: round(float(x), 5) for k, x in zip(keys, s)}


# ---- indexing worker (background thread, niced) ----
jobs = queue.Queue()
stop_flag = threading.Event()
busy = threading.Event()


def indexer():
    try:
        os.nice(10)
    except OSError:
        pass
    while True:
        items = jobs.get()
        busy.set()
        stop_flag.clear()
        todo = [(k, p) for k, p in items if k not in index and os.path.exists(p)]
        done = 0
        for k, p in todo:
            if stop_flag.is_set():
                break
            try:
                add(k, embed_image(p))
            except Exception as e:  # unreadable thumbnail: skip it
                emit({"event": "error", "key": k, "error": str(e)})
            done += 1
            if done % 16 == 0:
                save()
            emit({"event": "progress", "done": done, "total": len(todo)})
        save()
        sessions.pop("image", None)  # free ~0.5 GB until the next run
        emit({"event": "indexed", "count": len(keys)})
        busy.clear()


threading.Thread(target=indexer, daemon=True).start()

# ---- commands ----
last = time.time()
cmds = queue.Queue()


def reader():
    for line in sys.stdin:
        cmds.put(line)
    cmds.put(None)


threading.Thread(target=reader, daemon=True).start()
emit({"event": "ready", "count": len(keys)})

while True:
    try:
        line = cmds.get(timeout=5)
    except queue.Empty:
        if not busy.is_set() and time.time() - last > idle_sec:
            break
        continue
    if line is None:
        break
    last = time.time()
    try:
        c = json.loads(line)
    except ValueError:
        continue
    op = c.get("cmd")
    if op == "index":
        jobs.put(c.get("items", []))
    elif op == "stop":
        stop_flag.set()
    elif op == "query":
        emit({"event": "scores", "id": c.get("id"), "scores": scores_for(embed_text(c.get("text", "")))})
    elif op == "similar":
        with store_lock:
            i = index.get(c.get("key"))
            v = vecs[i].astype(np.float32) if i is not None else None
        emit({"event": "scores", "id": c.get("id"), "scores": scores_for(v) if v is not None else {}})
    elif op == "forget":
        keep = set(c.get("keep", []))
        with store_lock:
            sel = [i for i, k in enumerate(keys) if k in keep]
            keys[:] = [keys[i] for i in sel]
            vecs = vecs[sel]
            index.clear()
            index.update({k: i for i, k in enumerate(keys)})
        save()
emit({"event": "exit"})
