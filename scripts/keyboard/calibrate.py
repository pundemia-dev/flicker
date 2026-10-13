#!/usr/bin/env python3
"""Measure where a window's text caret really is (services/Caret.qml).

text-input-v3 reports the caret in SURFACE coords; toolkits with client-side
margins (GTK: shadow / resize border, different per window type — 19/17 px
on a zenity dialog, 12/20 on a zenity text window) put the surface origin
up-left of the window geometry the compositor IPC reports. Nothing exposes
that margin, so it is measured: the caret BLINKS, so the difference between
a few captures of the window (driftwm `screenshot window` = exactly the
window geometry, logical px, PNG on stdout — no files) isolates it.

usage: calibrate.py <window id> <x> <y> <w> <h> [frames] [interval_s]
  x y w h = the caret rectangle text-input reported (surface-local)
stdout: {"dx": .., "dy": ..} (subtract from the rect) or {"none": "<why>"}
"""
import io
import json
import subprocess
import sys
import time

from PIL import Image, ImageChops


def capture(win_id):
    out = subprocess.run(["driftwm", "msg", "screenshot", "window", "--id", str(win_id), "-o", "-"],
                         capture_output=True, timeout=5)
    if out.returncode != 0 or not out.stdout:
        return None
    return Image.open(io.BytesIO(out.stdout)).convert("L")


def components(mask):
    """Connected components (4-neighbour) of a small binary PIL image."""
    w, h = mask.size
    px = mask.load()
    seen = set()
    comps = []
    for y in range(h):
        for x in range(w):
            if not px[x, y] or (x, y) in seen:
                continue
            stack = [(x, y)]
            seen.add((x, y))
            x0 = x1 = x
            y0 = y1 = y
            n = 0
            while stack:
                cx, cy = stack.pop()
                n += 1
                x0, x1, y0, y1 = min(x0, cx), max(x1, cx), min(y0, cy), max(y1, cy)
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < w and 0 <= ny < h and px[nx, ny] and (nx, ny) not in seen:
                        seen.add((nx, ny))
                        stack.append((nx, ny))
            comps.append((x0, y0, x1 + 1, y1 + 1, n))
    return comps


def main():
    win_id = int(sys.argv[1])
    rx, ry, rw, rh = (int(v) for v in sys.argv[2:6])
    frames = int(sys.argv[6]) if len(sys.argv) > 6 else 7
    interval = float(sys.argv[7]) if len(sys.argv) > 7 else 0.2
    reach = 64  # largest margin looked for (px left / up of the rect)

    shots = []
    for i in range(frames):
        im = capture(win_id)
        if im is None:
            print(json.dumps({"none": "capture failed"}))
            return
        shots.append(im)
        if i + 1 < frames:
            time.sleep(interval)
    size = shots[0].size
    if any(s.size != size for s in shots):
        print(json.dumps({"none": "window resized"}))
        return

    # Search box: the caret sits at most `reach` px up-left of the rect.
    box = (max(0, rx - reach), max(0, ry - reach), min(size[0], rx + rw + 8), min(size[1], ry + rh + 8))
    if box[2] <= box[0] or box[3] <= box[1]:
        print(json.dumps({"none": "rect outside window"}))
        return
    crops = [s.crop(box) for s in shots]
    changed = None
    for a, b in zip(crops, crops[1:]):
        d = ImageChops.difference(a, b).point(lambda v: 255 if v > 40 else 0)
        changed = d if changed is None else ImageChops.lighter(changed, d)
    if changed is None or changed.getbbox() is None:
        print(json.dumps({"none": "no blink"}))
        return

    want_h = max(rh, 1)
    best = None
    for x0, y0, x1, y1, n in components(changed):
        cw, ch = x1 - x0, y1 - y0
        # A caret: a bar about the rect's height (or the rect's block for a
        # terminal cell), solid enough. Glyph edits would be wider / ragged.
        if ch < 0.5 * want_h or ch > 2.2 * want_h + 4 or cw > max(rw, 4) + 4 or n < 0.5 * cw * ch:
            continue
        # Centres, not corners: GTK entries report the whole field box
        # (34 px) around a 22 px caret.
        gx, gy = box[0] + x0 + cw / 2, box[1] + y0 + ch / 2
        dx, dy = round(rx + rw / 2 - gx), round(ry + rh / 2 - gy)
        score = abs(dx) + abs(dy)
        if best is None or score < best[0]:
            best = (score, dx, dy)
    if best is None:
        print(json.dumps({"none": "no caret-shaped blink"}))
        return
    print(json.dumps({"dx": best[1], "dy": best[2]}))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # never leave QML without an answer
        print(json.dumps({"none": "error: %s" % e}))
