#!/usr/bin/env python3
#
# GIF search backend for the launcher plugin `!gif`
# (modules/launcher/plugins/gifs). Stdlib only. Reads ONE JSON request line
# from stdin (keeps the API key out of argv, which /proc shows to every
# process of the user) and prints JSON lines to stdout.
#
# Request (search):
#   {"action": "search", "provider": "giphy|tenor", "key": "...",
#    "query": "" (= trending), "offset": "" (paging token from "page"),
#    "limit": 24, "rating": "pg-13", "locale": "en", "cacheDir": "...",
#    "cacheDays": 3}
# Output:
#   {"page": {"items": [{"id", "title", "page", "url", "full",
#             "width", "height", "preview": "<local path>"}], "next": "..."}}
#   {"ready": "<id>"}     preview downloaded (one per item, any order)
#   {"error": "<message>"}
#
# `search.py fetch <url> <cacheDir>`: downloads one GIF (the copy), prints
# its local path.
#
# Downloads happen here, not in Qt: Qt's network Image loader stalls
# silently when IPv6 is broken, urllib is forced onto IPv4 below.

import hashlib
import json
import os
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import threading
from concurrent.futures import ThreadPoolExecutor

TIMEOUT = 15
UA = "Flicker-Launcher/1.0"

_orig_getaddrinfo = socket.getaddrinfo


def _v4_getaddrinfo(host, port, family=0, *args, **kwargs):
    return _orig_getaddrinfo(host, port, socket.AF_INET, *args, **kwargs)


socket.getaddrinfo = _v4_getaddrinfo


_out_lock = threading.Lock()


def out(obj):
    # Preview threads print too: one whole line at a time.
    with _out_lock:
        sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
        sys.stdout.flush()


def get_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


def cache_name(url, suffix):
    return hashlib.sha1(url.encode()).hexdigest()[:20] + suffix


def download(url, path):
    if os.path.exists(path) and os.path.getsize(path) > 0:
        os.utime(path)  # keep it out of the prune
        return path
    tmp = path + ".part"
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r, open(tmp, "wb") as f:
        while True:
            chunk = r.read(65536)
            if not chunk:
                break
            f.write(chunk)
    os.replace(tmp, path)
    return path


def prune(cache_dir, days):
    cutoff = time.time() - days * 86400
    try:
        for name in os.listdir(cache_dir):
            p = os.path.join(cache_dir, name)
            try:
                if os.path.getmtime(p) < cutoff:
                    os.remove(p)
            except OSError:
                pass
    except OSError:
        pass


def _int(v, default=0):
    try:
        return int(v)
    except (TypeError, ValueError):
        return default


def search_giphy(req):
    key = req["key"]
    limit = _int(req.get("limit"), 24)
    offset = _int(req.get("offset"), 0)
    params = {"api_key": key, "limit": limit, "offset": offset,
              "rating": req.get("rating") or "pg-13"}
    query = (req.get("query") or "").strip()
    if query:
        params["q"] = query
        params["lang"] = (req.get("locale") or "en")[:2]
        endpoint = "search"
    else:
        endpoint = "trending"
    data = get_json(f"https://api.giphy.com/v1/gifs/{endpoint}?" + urllib.parse.urlencode(params))
    items = []
    for g in data.get("data") or []:
        im = g.get("images") or {}
        prev = im.get("fixed_width") or im.get("fixed_width_downsampled") or im.get("downsized") or {}
        full = im.get("downsized_medium") or im.get("original") or prev
        if not prev.get("url"):
            continue
        items.append({
            "id": "giphy-" + str(g.get("id")),
            "title": g.get("title") or "",
            "page": g.get("url") or "",
            "url": prev["url"],
            "full": full.get("url") or prev["url"],
            "width": _int(prev.get("width"), 200),
            "height": _int(prev.get("height"), 200),
        })
    pag = data.get("pagination") or {}
    total = _int(pag.get("total_count"), 0)
    nxt = offset + _int(pag.get("count"), len(items))
    return items, (str(nxt) if items and nxt < total else "")


def search_tenor(req):
    params = {"key": req["key"], "client_key": "flicker",
              "limit": _int(req.get("limit"), 24),
              "media_filter": "tinygif,gif",
              "contentfilter": {"g": "high", "pg": "medium", "pg-13": "low", "r": "off"}
              .get(req.get("rating") or "pg-13", "low"),
              "locale": req.get("locale") or "en"}
    if req.get("offset"):
        params["pos"] = req["offset"]
    query = (req.get("query") or "").strip()
    if query:
        params["q"] = query
        endpoint = "search"
    else:
        endpoint = "featured"
    data = get_json(f"https://tenor.googleapis.com/v2/{endpoint}?" + urllib.parse.urlencode(params))
    items = []
    for g in data.get("results") or []:
        mf = g.get("media_formats") or {}
        prev = mf.get("tinygif") or mf.get("gif") or {}
        full = mf.get("gif") or prev
        if not prev.get("url"):
            continue
        dims = prev.get("dims") or [200, 200]
        items.append({
            "id": "tenor-" + str(g.get("id")),
            "title": g.get("content_description") or g.get("title") or "",
            "page": g.get("itemurl") or "",
            "url": prev["url"],
            "full": full.get("url") or prev["url"],
            "width": _int(dims[0], 200),
            "height": _int(dims[1] if len(dims) > 1 else 200, 200),
        })
    return items, (data.get("next") or "") if items else ""


def http_error(e):
    if isinstance(e, urllib.error.HTTPError):
        if e.code in (401, 403):
            return f"API key rejected (HTTP {e.code})"
        if e.code == 429:
            return "Rate limit reached (HTTP 429)"
        return f"HTTP {e.code}"
    if isinstance(e, urllib.error.URLError):
        return f"Network error: {e.reason}"
    return str(e) or e.__class__.__name__


def do_search(req):
    cache_dir = req.get("cacheDir") or os.path.expanduser("~/.cache/flicker/gifs")
    os.makedirs(cache_dir, exist_ok=True)
    prune(cache_dir, float(req.get("cacheDays") or 3))
    provider = req.get("provider")
    fn = {"giphy": search_giphy, "tenor": search_tenor}.get(provider)
    if not fn:
        out({"error": f"Unknown provider: {provider}"})
        return
    try:
        items, nxt = fn(req)
    except Exception as e:  # noqa: BLE001 — one readable line for the UI
        out({"error": http_error(e)})
        return
    for it in items:
        it["preview"] = os.path.join(cache_dir, cache_name(it["url"], ".gif"))
    out({"page": {"items": items, "next": nxt}})

    def fetch(it):
        try:
            download(it["url"], it["preview"])
            out({"ready": it["id"]})
        except Exception:  # noqa: BLE001 — a missing tile stays a placeholder
            pass

    # Top rows first: the pool takes them in order.
    with ThreadPoolExecutor(max_workers=6) as pool:
        list(pool.map(fetch, items))


def main():
    # `search.py fetch <url> <cacheDir>` prints the local path (copy from a
    # detached shell: the plugin is gone once the launcher closes).
    if len(sys.argv) == 4 and sys.argv[1] == "fetch":
        url, cache_dir = sys.argv[2], sys.argv[3]
        os.makedirs(cache_dir, exist_ok=True)
        try:
            print(download(url, os.path.join(cache_dir, cache_name(url, "-full.gif"))))
        except Exception as e:  # noqa: BLE001
            print(http_error(e), file=sys.stderr)
            sys.exit(1)
        return
    line = sys.stdin.readline()
    try:
        req = json.loads(line)
    except ValueError:
        out({"error": "bad request"})
        return
    do_search(req)


if __name__ == "__main__":
    main()
