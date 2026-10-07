#!/usr/bin/env python3
"""Visual duplicate finder for the wallpaper carousel (services/WallpaperDupes).

Usage: dupes.py <cacheDir> <maxDistance> <maxPixel> <maxMean> <maxZ> <flatStd>
       (stdin: "key\\tpath" lines)

Works on the carousel thumbnails (<cacheDir>/<key>.jpg), so the same picture
in another resolution / format / compression matches:
  * candidates: dHash (9x8 greyscale gradient, 64 bit) within maxDistance,
    found through 8 bands of 8 bits (pigeonhole: distance <= 7 shares one);
  * verified on a 16x16 RGB miniature: every channel within maxPixel, the
    mean difference within maxMean, AND the contrast-normalised luminance
    (z-scores) within maxZ mean difference — box averaging hides small
    details, normalising brings them back (measured on the user's folder:
    real duplicates 0.003-0.13, distinct dark/minimal ones 0.26+). Nearly
    flat miniatures (luminance std < flatStd: z-scores are noise there)
    must instead match almost exactly (every channel within 8). dHash
    alone glued hundreds of dark / minimal wallpapers and recolours of one
    drawing; a real duplicate differs only by resampling / compression.
  * groups form around a representative (the first member) — no chaining
    A~B~C into one giant group.
Fingerprints are cached in <cacheDir>/dhash.json by thumbnail key.
Prints JSON: {"groups": [[{path, w, h, bytes}, ...], ...], "hashed": n,
"missing": n} — each group biggest picture first.
"""
import base64
import json
import os
import sys

from PIL import Image

cache_dir, max_dist, max_pixel, max_mean = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), float(sys.argv[4])
max_z, flat_std = float(sys.argv[5]), float(sys.argv[6])
FLAT_PIXEL = 8
cache_file = os.path.join(cache_dir, "dhash.json")
VERSION = 2
try:
    with open(cache_file) as f:
        cache = json.load(f)
    if cache.get("_v") != VERSION:
        cache = {}
except (OSError, ValueError):
    cache = {}
cache["_v"] = VERSION


def fingerprint(thumb):
    with Image.open(thumb) as im:
        im = im.convert("RGB")
        px = im.convert("L").resize((9, 8), Image.Resampling.BILINEAR).tobytes()
        bits = 0
        for y in range(8):
            for x in range(8):
                bits = (bits << 1) | (px[y * 9 + x] > px[y * 9 + x + 1])
        mini = im.resize((16, 16), Image.Resampling.BOX).tobytes()
    return [format(bits, "016x"), base64.b64encode(mini).decode()]


items, missing, changed = [], 0, False
for line in sys.stdin:
    key, _, path = line.rstrip("\n").partition("\t")
    if not path:
        continue
    fp = cache.get(key)
    if fp is None:
        thumb = os.path.join(cache_dir, key + ".jpg")
        if not os.path.exists(thumb):
            missing += 1
            continue
        try:
            fp = fingerprint(thumb)
        except OSError:
            missing += 1
            continue
        cache[key] = fp
        changed = True
    items.append((path, int(fp[0], 16), base64.b64decode(fp[1])))

if changed:
    tmp = cache_file + ".tmp"
    with open(tmp, "w") as f:
        json.dump(cache, f)
    os.replace(tmp, cache_file)

def luma(mini):
    g = [(mini[k] * 299 + mini[k + 1] * 587 + mini[k + 2] * 114) / 1000 for k in range(0, len(mini), 3)]
    m = sum(g) / len(g)
    sd = (sum((x - m) ** 2 for x in g) / len(g)) ** 0.5
    return sd, [(x - m) / (sd or 1) for x in g]


norm = {}


def normed(i):
    if i not in norm:
        norm[i] = luma(items[i][2])
    return norm[i]


def same(i, j):
    if (items[i][1] ^ items[j][1]).bit_count() > max_dist:
        return False
    sa, za = normed(i)
    sb, zb = normed(j)
    flat = min(sa, sb) < flat_std
    limit = FLAT_PIXEL if flat else max_pixel
    a, b = items[i][2], items[j][2]
    total = 0
    for x, y in zip(a, b):
        d = abs(x - y)
        if d > limit:
            return False
        total += d
    if total / len(a) > max_mean:
        return False
    return flat or sum(abs(x - y) for x, y in zip(za, zb)) / len(za) <= max_z


# Candidate neighbours through the bands.
bands = {}
for i, (_, h, _) in enumerate(items):
    for b in range(8):
        bands.setdefault((b, (h >> (8 * b)) & 0xFF), []).append(i)
near = {}
for members in bands.values():
    for a in range(len(members)):
        for j in members[a + 1:]:
            near.setdefault(members[a], set()).add(j)
            near.setdefault(j, set()).add(members[a])

# Groups around a representative: an item joins the group of the first
# earlier representative it truly matches; otherwise it starts its own.
group_of = {}
groups = {}
for i in range(len(items)):
    home = i
    for j in sorted(near.get(i, ())):
        if j >= i:
            break
        if group_of.get(j) == j and same(i, j):
            home = j
            break
    group_of[i] = home
    groups.setdefault(home, []).append(i)


def describe(path):
    w = h = 0
    try:
        with Image.open(path) as im:
            w, h = im.size
    except OSError:
        pass  # video, or unreadable: resolution unknown
    try:
        size = os.path.getsize(path)
    except OSError:
        size = 0
    return {"path": path, "w": w, "h": h, "bytes": size}


out = []
for members in groups.values():
    if len(members) < 2:
        continue
    g = [describe(items[i][0]) for i in members]
    g.sort(key=lambda d: (-(d["w"] * d["h"]), -d["bytes"], d["path"]))
    out.append(g)
out.sort(key=lambda g: os.path.basename(g[0]["path"]).lower())
json.dump({"groups": out, "hashed": len(items), "missing": missing}, sys.stdout)
