#!/usr/bin/env -S uv run --script --quiet
# /// script
# requires-python = ">=3.11"
# dependencies = ["opencv-contrib-python-headless"]
# ///
"""Detect content boxes on a screenshot (port of end-4 find_regions.py; via pShell).

Usage: capture_regions.py <image>
Prints a JSON array of {x, y, width, height} in image (physical) pixels.

Selective search (opencv ximgproc) runs on a downscaled copy for speed;
results are filtered by size and deduplicated with IoU-based NMS. Any
failure prints [] — the selector must keep working without this feature.
"""

import json
import sys


def iou(a, b):
    x1 = max(a["x"], b["x"])
    y1 = max(a["y"], b["y"])
    x2 = min(a["x"] + a["width"], b["x"] + b["width"])
    y2 = min(a["y"] + a["height"], b["y"] + b["height"])
    inter = max(0, x2 - x1) * max(0, y2 - y1)
    union = a["width"] * a["height"] + b["width"] * b["height"] - inter
    return inter / union if union > 0 else 0


def nms(regions, threshold=0.7):
    regions = sorted(regions, key=lambda r: r["width"] * r["height"], reverse=True)
    keep = []
    while regions:
        cur = regions.pop(0)
        keep.append(cur)
        regions = [r for r in regions if iou(cur, r) < threshold]
    return keep


def main():
    try:
        import cv2

        img = cv2.imread(sys.argv[1])
        if img is None:
            print("[]")
            return
        h, w = img.shape[:2]
        # 640px cap: selective search cost grows steeply with resolution, and
        # snap targets don't need pixel-perfect boxes (the box stays adjustable).
        rf = min(1.0, 640.0 / max(w, h))
        small = cv2.resize(img, (int(w * rf), int(h * rf)), interpolation=cv2.INTER_AREA)
        ss = cv2.ximgproc.segmentation.createSelectiveSearchSegmentation()
        ss.setBaseImage(small)
        ss.switchToSelectiveSearchFast(150, 20, 0.8)
        rects = ss.process()

        min_px = 48
        out = []
        for x, y, rw, rh in rects:
            r = {
                "x": int(x / rf),
                "y": int(y / rf),
                "width": int(rw / rf),
                "height": int(rh / rf),
            }
            if r["width"] < min_px or r["height"] < min_px:
                continue
            if r["width"] > 0.95 * w and r["height"] > 0.95 * h:
                continue
            out.append(r)
        print(json.dumps(nms(out)[:80]))
    except Exception:
        print("[]")


if __name__ == "__main__":
    main()
