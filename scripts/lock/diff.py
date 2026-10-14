#!/usr/bin/env python3
"""Regions of a screen grab that differ from the wallpaper under them.

Usage: diff.py <grab> <wallpaper> [--grid N] [--threshold T] [--dilate D]
               [--min-cells M] [--max-coverage C]

Both images are reduced to a grid of N columns (wallpaper cover-fitted the way
wallr "fill" shows it), compared per cell (max channel difference after a small
blur, so scaling filters / dithering stay below T), dilated by D cells and split
into connected components. Overlapping component boxes are merged.
Prints one JSON object: {"w","h","coverage","regions":[{x,y,w,h,area}]} in
grab pixels, regions sorted largest first. --hole + --inpaint-out also write
the grab with that rect painted out ("inpainted": path). coverage > C (or a failure to read
the wallpaper) -> one region = the whole grab ("whole": true).
"""
import argparse
import json
import sys

from PIL import Image, ImageChops, ImageFilter


def cover(img, w, h):
    s = max(w / img.width, h / img.height)
    sw, sh = round(img.width * s), round(img.height * s)
    img = img.resize((sw, sh), Image.BOX)
    l, t = (sw - w) // 2, (sh - h) // 2
    return img.crop((l, t, l + w, t + h))


def components(mask, gw, gh, min_cells):
    """Bounding boxes of 4-connected components, labelled by row runs
    (union-find over runs: ~10x fewer steps than a per-cell flood fill)."""
    runs = []  # [x0, x1, y]
    parent = []

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    prev = []
    for y in range(gh):
        row = mask[y * gw:(y + 1) * gw]
        cur = []
        x = 0
        while x < gw:
            if row[x]:
                s = x
                while x < gw and row[x]:
                    x += 1
                i = len(runs)
                runs.append((s, x, y))
                parent.append(i)
                cur.append(i)
            else:
                x += 1
        j = 0
        for i in cur:  # union with overlapping runs of the previous row
            s, e, _ = runs[i]
            while j < len(prev) and runs[prev[j]][1] <= s:
                j += 1
            k = j
            while k < len(prev) and runs[prev[k]][0] < e:
                ri, rk = find(i), find(prev[k])
                if ri != rk:
                    parent[ri] = rk
                k += 1
        prev = cur

    boxes = {}
    for i, (s, e, y) in enumerate(runs):
        r = find(i)
        b = boxes.get(r)
        if b is None:
            boxes[r] = [s, y, e, y + 1, e - s]
        else:
            b[0], b[1], b[2], b[3] = min(b[0], s), min(b[1], y), max(b[2], e), max(b[3], y + 1)
            b[4] += e - s
    return [b[:4] for b in boxes.values() if b[4] >= min_cells]


def merge(boxes):
    changed = True
    while changed:
        changed = False
        for a in range(len(boxes)):
            for b in range(a + 1, len(boxes)):
                p, q = boxes[a], boxes[b]
                if p[0] < q[2] and q[0] < p[2] and p[1] < q[3] and q[1] < p[3]:
                    boxes[a] = [min(p[0], q[0]), min(p[1], q[1]),
                                max(p[2], q[2]), max(p[3], q[3])]
                    del boxes[b]
                    changed = True
                    break
            if changed:
                break
    return boxes


def inpaint(grab, hole, strip, radius, out):
    """Paint the island out of the grab: the `strip` px rows just below the
    hole, stretched over it and blurred (the lock's password field flies off
    from there — the grab's own island must not stay behind)."""
    x, y, w, h = (round(v) for v in hole)
    W, H = grab.size
    x0, y0, x1, y1 = max(0, x), max(0, y), min(W, x + w), min(H, y + h)
    if x1 <= x0 or y1 <= y0:
        return None
    sy = min(H - strip, y1)
    if sy < 0:
        return None
    patch = grab.crop((x0, sy, x1, sy + strip)).resize((x1 - x0, y1 - y0), Image.BILINEAR)
    if radius > 0:
        patch = patch.filter(ImageFilter.GaussianBlur(radius))
    img = grab.copy()
    img.paste(patch, (x0, y0))
    img.save(out, "PPM")
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("grab")
    ap.add_argument("wallpaper")
    ap.add_argument("--grid", type=int, default=240)
    ap.add_argument("--threshold", type=int, default=20)
    ap.add_argument("--dilate", type=int, default=1)
    ap.add_argument("--min-cells", type=int, default=4)
    ap.add_argument("--max-coverage", type=float, default=0.85)
    ap.add_argument("--hole", default="", help="x,y,w,h in grab px: inpaint it")
    ap.add_argument("--inpaint-out", default="")
    ap.add_argument("--strip", type=int, default=3)
    ap.add_argument("--inpaint-blur", type=float, default=8)
    ap.add_argument("--no-diff", action="store_true",
                    help="moving wallpaper: only inpaint, no regions")
    a = ap.parse_args()

    grab = Image.open(a.grab).convert("RGB")
    W, H = grab.size
    extra = {}
    if a.hole and a.inpaint_out:
        try:
            done = inpaint(grab, [float(v) for v in a.hole.split(",")], a.strip, a.inpaint_blur, a.inpaint_out)
            if done:
                extra["inpainted"] = done
        except Exception as e:  # noqa: BLE001 — no inpaint = the raw grab
            print(f"diff: inpaint: {e}", file=sys.stderr)
    whole = {"w": W, "h": H, "coverage": 1.0, "whole": True,
             "regions": [{"x": 0, "y": 0, "w": W, "h": H, "area": W * H}]}
    if a.no_diff:
        print(json.dumps({"w": W, "h": H, "coverage": 0, "whole": False, "regions": [], **extra}))
        return
    gw = a.grid
    gh = max(1, round(gw * H / W))
    try:
        wall = Image.open(a.wallpaper)
        # JPEG: decode at the smallest DCT scale still >= the grid (fast).
        wall.draft("RGB", (gw * 2, gh * 2))
        wall = cover(wall.convert("RGB"), gw, gh)
    except Exception as e:  # noqa: BLE001 — any unreadable wallpaper = whole
        print(f"diff: wallpaper: {e}", file=sys.stderr)
        print(json.dumps({**whole, **extra}))
        return

    blur = ImageFilter.BoxBlur(1)
    g = grab.resize((gw, gh), Image.BOX).filter(blur)
    w = wall.filter(blur)
    d = ImageChops.difference(g, w)
    r, gr, b = d.split()
    m = ImageChops.lighter(ImageChops.lighter(r, gr), b)
    m = m.point(lambda v: 255 if v > a.threshold else 0)
    if a.dilate > 0:
        m = m.filter(ImageFilter.MaxFilter(a.dilate * 2 + 1))
    mask = m.tobytes()
    coverage = sum(1 for v in mask if v) / (gw * gh)
    if coverage > a.max_coverage:
        whole["coverage"] = round(coverage, 3)
        print(json.dumps({**whole, **extra}))
        return

    boxes = merge(components(mask, gw, gh, a.min_cells))
    sx, sy = W / gw, H / gh
    regions = []
    for x0, y0, x1, y1 in boxes:
        x, y = int(x0 * sx), int(y0 * sy)
        rw, rh = min(W, round(x1 * sx)) - x, min(H, round(y1 * sy)) - y
        regions.append({"x": x, "y": y, "w": rw, "h": rh, "area": rw * rh})
    regions.sort(key=lambda q: -q["area"])
    print(json.dumps({"w": W, "h": H, "coverage": round(coverage, 3),
                      "whole": False, "regions": regions, **extra}))


if __name__ == "__main__":
    main()
