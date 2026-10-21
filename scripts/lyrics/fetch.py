#!/usr/bin/env python3
"""Song lyrics for services/Lyrics.qml.

Usage: fetch.py --artist A --title T [--album B] [--duration S] [--file PATH]
                --cache DIR [--sources local,lrclib,netease,genius]
                [--timeout S] [--deadline S] [--none-ttl S] [--max-diff S]

Prints ONE JSON object on stdout:
  {"status": "ok", "source": name, "synced": bool, "instrumental": bool,
   "lines": [{"t": seconds (-1 = unsynced), "x": text}, ...]}
  {"status": "none"}                    nothing matched (cached --none-ttl s)
Exit 1 = network error and nothing found (not cached, the shell may retry).
Plain text found while another source failed is cached with "partial" and
expires like a miss (that source may have had synced lines).
Values may start with "-": pass them as --title=VALUE.

Sources, best first (synced beats plain whatever the source):
  local    <audio file>.lrc / .txt next to a local track (--file)
  lrclib   lrclib.net: exact /api/get, then scored searches over name variants
  netease  music.163.com: synced LRC, decent for Russian pop / rap that
           lrclib lacks; strict title + artist + duration match
  genius   genius.com: plain text only, the widest Russian rap / indie
           coverage; strict title + artist match (no duration there)
Measured on a 1500-track mostly Russian library (Oct 2026): lrclib alone
found ~69% of Russian tracks; most misses were "A/B" artist tags, "(из
фильма …)"-style title tails, lrclib 503s, and niche artists only Genius /
NetEase know.

Name variants: raw; cleaned ("(feat. X)", "(Official Video)", "- Remastered
2011", "Artist - Topic", "XVEVO"); every artist of "A/B", "A, B", "A feat. B";
the title without any (…)/[…] tail; a browser/YouTube "Artist - Song" title
split apart. IPv4 only: IPv6 is broken on some networks and urllib would
stall on it first.
"""

import argparse
import hashlib
import json
import os
import re
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser

LRCLIB = "https://lrclib.net/api"
UA = "flicker-shell (quickshell; lyrics module)"
BROWSER_UA = "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0"

_orig_getaddrinfo = socket.getaddrinfo


def _v4_getaddrinfo(host, port, family=0, *args, **kwargs):
    return _orig_getaddrinfo(host, port, socket.AF_INET, *args, **kwargs)


socket.getaddrinfo = _v4_getaddrinfo


class NetError(Exception):
    pass


# Whole-lookup budget (--deadline): a hanging host must not keep the panel
# on "searching" for minutes (up to ~10 requests x timeout x retries).
DEADLINE = float("inf")


def http_get(url, headers, timeout, retries=2, as_json=True):
    left = DEADLINE - time.monotonic()
    if left <= 0:
        raise NetError("deadline")
    timeout = min(timeout, left)
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            body = r.read().decode("utf-8", "replace")
        return json.loads(body) if as_json else body
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        # lrclib answers 503 / 429 under bursts: back off and retry.
        if (e.code >= 500 or e.code == 429) and retries > 0:
            time.sleep(1.5 if retries > 1 else 3)
            return http_get(url, headers, timeout, retries - 1, as_json)
        raise NetError(f"HTTP {e.code}") from e
    except (urllib.error.URLError, TimeoutError, OSError, ValueError) as e:
        raise NetError(str(e)) from e


# --- names ------------------------------------------------------------------

_JUNK = re.compile(
    r"\s*[(\[]\s*(?:official|lyrics?|audio|video|music video|visuali[sz]er|hd|hq|4k|"
    r"explicit|clean|mv|m/v|live|remaster(?:ed)?|\d{4} remaster(?:ed)?|"
    r"feat\.?|ft\.?|featuring|prod\.?|with )[^)\]]*[)\]]",
    re.I,
)
_DASH_TAIL = re.compile(r"\s+-\s+(?:.*remaster(?:ed)?.*|.*version|.*edit|.*mix|live.*|mono|stereo)$", re.I)
_FEAT = re.compile(r"\s+(?:feat\.?|ft\.?|featuring)\s+.*$", re.I)
_PARENS = re.compile(r"\s*[(\[][^)\]]*[)\]]")
# Not "и" / "and": "Король и Шут", "Simon and Garfunkel" are one artist.
_ARTIST_SPLIT = re.compile(r"\s*(?:/|;|,|&|\s+[x×]\s+|\bfeat\.?|\bft\.?)\s*", re.I)


def clean_title(t):
    t = _JUNK.sub("", t)
    t = _DASH_TAIL.sub("", t)
    t = _FEAT.sub("", t)
    t = t.split(" | ")[0]
    return t.strip(" -–—\"'")


def bare_title(t):
    return _PARENS.sub("", clean_title(t)).strip(" -–—\"'") or clean_title(t)


def clean_artist(a):
    a = re.sub(r"\s*-\s*Topic$", "", a)
    a = re.sub(r"VEVO$", "", a)
    a = re.sub(r"\s*(?:Official|Music)$", "", a, flags=re.I)
    return a.strip()


def artist_parts(a):
    seen = []
    for p in _ARTIST_SPLIT.split(a):
        p = p.strip()
        if p and p not in seen:
            seen.append(p)
    return seen


def first_artist(a):
    return (artist_parts(a) or [a])[0]


def norm(s):
    return re.sub(r"[^\w]+", "", (s or "").casefold().replace("ё", "е"))


def artist_match(theirs, ours):
    """Any artist of `theirs` (str or list) matches any of `ours`."""
    names = theirs if isinstance(theirs, list) else [theirs]
    want = {norm(p) for p in artist_parts(ours)} | {norm(ours)}
    have = set()
    for n in names:
        have |= {norm(n), norm(_PARENS.sub("", n))}
        have |= {norm(x) for x in re.findall(r"\(([^)]*)\)", n)}  # "КИНО (KINO)"
        have |= {norm(p) for p in artist_parts(n)}
    want.discard("")
    have.discard("")
    return any(w == h or (len(w) > 2 and len(h) > 2 and (w in h or h in w)) for w in want for h in have)


def title_match(theirs, ours):
    t = norm(bare_title(theirs))
    return t != "" and t in (norm(bare_title(ours)), norm(clean_title(ours)), norm(ours))


def variants(artist, title):
    out = []

    def add(a, t):
        a, t = a.strip(), t.strip()
        if t and (a, t) not in out:
            out.append((a, t))

    ca, ct, bt = clean_artist(artist), clean_title(title), bare_title(title)
    add(artist, title)
    add(ca, ct)
    for p in artist_parts(ca)[:3]:
        add(p, ct)
    add(first_artist(ca), bt)
    # Browser players: "Artist - Song (Official Video)" with the channel as artist.
    if " - " in title:
        left, right = title.split(" - ", 1)
        left = clean_artist(left)
        add(left, clean_title(right))
        add(first_artist(left), bare_title(right))
    return out


# --- LRC --------------------------------------------------------------------

_TAG = re.compile(r"\[(\d+):(\d+(?:[.:]\d+)?)\]")
_WORD = re.compile(r"<\d+:\d+(?:[.:]\d+)?>")
_OFFSET = re.compile(r"\[offset:\s*([+-]?\d+)\]", re.I)


def parse_lrc(text):
    off = _OFFSET.search(text)
    shift = int(off.group(1)) / 1000 if off else 0.0
    out = []
    for raw in text.splitlines():
        stamps = []
        pos = 0
        while True:
            m = _TAG.match(raw, pos)
            if not m:
                break
            sec = m.group(2).replace(":", ".")
            stamps.append(int(m.group(1)) * 60 + float(sec))
            pos = m.end()
        if not stamps:
            continue
        line = _WORD.sub("", raw[pos:]).strip()
        for s in stamps:
            out.append({"t": round(max(0.0, s - shift), 3), "x": line})
    out.sort(key=lambda l: l["t"])
    return out


def plain_lines(text):
    lines = [l.strip() for l in text.strip().splitlines()]
    # Collapse runs of blank lines into one stanza break.
    out = []
    for l in lines:
        if l or (out and out[-1]["x"]):
            out.append({"t": -1, "x": l})
    return out


def result(source, synced=None, plain=None, instrumental=False):
    if instrumental:
        return {"status": "ok", "source": source, "synced": False, "instrumental": True, "lines": []}
    if synced:
        return {"status": "ok", "source": source, "synced": True, "instrumental": False, "lines": synced}
    if plain:
        return {"status": "ok", "source": source, "synced": False, "instrumental": False, "lines": plain}
    return None


# --- local ------------------------------------------------------------------


def from_local(path):
    if not path:
        return None
    stem = os.path.splitext(path)[0]
    for ext in (".lrc", ".LRC"):
        try:
            with open(stem + ext, encoding="utf-8", errors="replace") as f:
                text = f.read()
        except OSError:
            continue
        lines = parse_lrc(text)
        return result("local", synced=lines) or result("local", plain=plain_lines(text))
    try:
        with open(stem + ".txt", encoding="utf-8", errors="replace") as f:
            return result("local", plain=plain_lines(f.read()))
    except OSError:
        return None


# --- lrclib -----------------------------------------------------------------


def lrclib_get(path, params, timeout):
    url = f"{LRCLIB}/{path}?{urllib.parse.urlencode(params)}"
    return http_get(url, {"User-Agent": UA}, timeout)


def lrclib_score(rec, title, artist, duration, max_diff):
    if not (rec.get("syncedLyrics") or rec.get("plainLyrics") or rec.get("instrumental")):
        return None
    # A same-length song of the same artist is not a match: the title must
    # agree; the artist too when there is no duration to check against.
    if not title_match(rec.get("trackName"), title):
        return None
    a_ok = bool(artist) and artist_match(rec.get("artistName"), artist)
    s = 0.0
    d = rec.get("duration") or 0
    if duration > 0 and d > 0:
        diff = abs(d - duration)
        if diff > max_diff:
            return None
        s -= diff
    elif not a_ok:
        return None
    if rec.get("syncedLyrics"):
        s += 20
    if a_ok:
        s += 10
    return s


def lrclib_best(recs, title, artist, duration, max_diff):
    scored = [(lrclib_score(r, title, artist, duration, max_diff), r) for r in recs or []]
    scored = [x for x in scored if x[0] is not None]
    return max(scored, key=lambda x: x[0])[1] if scored else None


def lrclib_result(rec):
    if not rec:
        return None
    if rec.get("instrumental"):
        return result("lrclib", instrumental=True)
    return (result("lrclib", synced=parse_lrc(rec.get("syncedLyrics") or ""))
            or result("lrclib", plain=plain_lines(rec.get("plainLyrics") or "")))


def from_lrclib(artist, title, album, duration, vs, timeout, max_diff):
    if duration > 0 and artist:
        res = lrclib_result(lrclib_get("get", {"track_name": title, "artist_name": artist,
                                               "album_name": album, "duration": round(duration)}, timeout))
        if res:
            return res
    found = None
    for a, t in vs:
        params = {"track_name": t}
        if a:
            params["artist_name"] = a
        rec = lrclib_best(lrclib_get("search", params, timeout), t, a, duration, max_diff)
        if rec:
            res = lrclib_result(rec)
            if res and (res["synced"] or res["instrumental"]):
                return res
            found = found or res
    if found:
        return found
    # Free text over the first variants (catches swapped / translit names).
    for a, t in vs[:2]:
        rec = lrclib_best(lrclib_get("search", {"q": f"{a} {t}".strip()}, timeout), t, a, duration, max_diff)
        if rec:
            return lrclib_result(rec)
    return None


# --- NetEase ----------------------------------------------------------------

NETEASE_HEADERS = {"User-Agent": BROWSER_UA, "Referer": "https://music.163.com/"}


def from_netease(vs, duration, timeout, max_diff):
    tried = set()
    for a, t in vs[:4]:
        q = f"{a} {t}".strip()
        if q in tried:
            continue
        tried.add(q)
        url = "https://music.163.com/api/search/get?" + urllib.parse.urlencode({"s": q, "type": 1, "limit": 8})
        songs = ((http_get(url, NETEASE_HEADERS, timeout) or {}).get("result") or {}).get("songs") or []
        for s in songs:
            d = (s.get("duration") or 0) / 1000
            if duration > 0 and d > 0 and abs(d - duration) > max_diff:
                continue
            if not title_match(s.get("name"), t):
                continue
            if not artist_match([x.get("name", "") for x in s.get("artists") or []], a):
                continue
            url = f"https://music.163.com/api/song/lyric?id={s['id']}&lv=1&kv=1&tv=-1"
            lrc = ((http_get(url, NETEASE_HEADERS, timeout) or {}).get("lrc") or {}).get("lyric") or ""
            lines = parse_lrc(lrc)
            # Lines like "作词 : X" / "作曲 : Y" are credits, not lyrics.
            lines = [l for l in lines if not re.match(r"^(作词|作曲|编曲|制作人|混音|母带)\s*[:：]", l["x"])]
            if len(lines) > 3:
                return result("netease", synced=lines)
    return None


# --- Genius -----------------------------------------------------------------


class _GeniusPage(HTMLParser):
    """Text of <div data-lyrics-container="true"> blocks, <br> = newline,
    skipping their data-exclude-from-selection headers."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.depth = 0
        self.skip = 0
        self.out = []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if self.depth:
            if tag == "br":
                self.out.append("\n")
                return
            self.depth += 1
            if not self.skip and a.get("data-exclude-from-selection") == "true":
                self.skip = self.depth
        elif tag == "div" and a.get("data-lyrics-container") == "true":
            self.depth = 1
            self.out.append("\n")

    def handle_startendtag(self, tag, attrs):
        if self.depth and tag == "br":
            self.out.append("\n")

    def handle_endtag(self, tag):
        if self.depth and tag != "br":
            if self.skip == self.depth:
                self.skip = 0
            self.depth -= 1

    def handle_data(self, data):
        if self.depth and not self.skip:
            self.out.append(data)


def from_genius(vs, timeout):
    headers = {"User-Agent": BROWSER_UA}
    tried = set()
    for a, t in vs[:4]:
        if not a:
            continue
        q = f"{a} {t}"
        if q in tried:
            continue
        tried.add(q)
        url = "https://genius.com/api/search/multi?" + urllib.parse.urlencode({"q": q})
        sections = (((http_get(url, headers, timeout) or {}).get("response") or {}).get("sections")) or []
        for sec in sections:
            if sec.get("type") not in ("top_hit", "song"):
                continue
            for h in sec.get("hits") or []:
                if h.get("type") != "song":
                    continue
                r = h.get("result") or {}
                primary = (r.get("primary_artist") or {}).get("name", "")
                # Genius' own translation / romanization accounts.
                if primary.startswith("Genius"):
                    continue
                artists = [primary] + [x.get("name", "") for x in r.get("featured_artists") or []]
                if not (title_match(r.get("title"), t) and artist_match(artists, a)):
                    continue
                if r.get("instrumental"):
                    return result("genius", instrumental=True)
                page = _GeniusPage()
                page.feed(http_get(r["url"], headers, timeout, as_json=False) or "")
                text = "".join(page.out)
                # [Куплет 1] / [Chorus] section headers.
                text = "\n".join(l for l in text.splitlines() if not re.fullmatch(r"\s*\[[^\]]*\]\s*", l))
                res = result("genius", plain=plain_lines(text))
                if res and len([l for l in res["lines"] if l["x"]]) > 2:
                    return res
    return None


# --- main -------------------------------------------------------------------


def lookup(artist, title, album, duration, timeout, max_diff, sources, file=""):
    vs = variants(artist, title)
    plain = None
    errors = []

    def take(res):
        nonlocal plain
        if res and (res["synced"] or res["instrumental"]):
            return res
        plain = plain or res
        return None

    steps = {
        "local": lambda: from_local(file),
        "lrclib": lambda: from_lrclib(artist, title, album, duration, vs, timeout, max_diff),
        "netease": lambda: from_netease(vs, duration, timeout, max_diff),
    }
    for name in sources:
        if name not in steps:
            continue
        try:
            res = take(steps[name]())
        except NetError as e:
            errors.append(f"{name}: {e}")
            continue
        if res:
            return res
    if not plain and "genius" in sources:
        try:
            plain = from_genius(vs, timeout)
        except NetError as e:
            errors.append(f"genius: {e}")
    if plain:
        # A source that might have had synced lines failed: expire like a
        # miss instead of pinning the plain text forever.
        if errors:
            plain["partial"] = True
        return plain
    if errors:
        raise NetError("; ".join(errors))
    return {"status": "none"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--artist", default="")
    ap.add_argument("--title", required=True)
    ap.add_argument("--album", default="")
    ap.add_argument("--duration", type=float, default=0)
    ap.add_argument("--file", default="")
    ap.add_argument("--cache", required=True)
    ap.add_argument("--sources", default="local,lrclib,netease,genius")
    ap.add_argument("--timeout", type=float, default=10)
    ap.add_argument("--none-ttl", type=float, default=43200)
    ap.add_argument("--max-diff", type=float, default=8)
    ap.add_argument("--deadline", type=float, default=30)
    args = ap.parse_args()
    global DEADLINE
    DEADLINE = time.monotonic() + args.deadline
    sources = [s.strip() for s in args.sources.split(",") if s.strip()]

    # Local files are re-read every time (cheap, and an added .lrc shows up).
    if "local" in sources:
        res = from_local(args.file)
        if res:
            print(json.dumps(res, ensure_ascii=False))
            return 0
        sources.remove("local")

    key = "|".join([norm(args.artist), norm(args.title), str(round(args.duration)), ",".join(sources)])
    path = os.path.join(args.cache, hashlib.md5(key.encode()).hexdigest() + ".json")
    try:
        with open(path, encoding="utf-8") as f:
            cached = json.load(f)
        final = cached.get("status") == "ok" and not cached.get("partial")
        if final or time.time() - cached.get("at", 0) < args.none_ttl:
            print(json.dumps(cached, ensure_ascii=False))
            return 0
    except (OSError, ValueError):
        pass

    try:
        res = lookup(args.artist, args.title, args.album, args.duration, args.timeout,
                     args.max_diff, sources)
    except NetError as e:
        print(f"lyrics: network error: {e}", file=sys.stderr)
        return 1
    res["at"] = int(time.time())
    os.makedirs(args.cache, exist_ok=True)
    tmp = path + ".part"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(res, f, ensure_ascii=False)
    os.replace(tmp, path)
    print(json.dumps(res, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
