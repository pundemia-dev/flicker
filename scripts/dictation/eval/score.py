#!/usr/bin/env python3
"""score.py — score eval results against cases.jsonl expectations.

Metrics per case:
  dist      word-level distance to expected (1 - difflib ratio, 0 = exact)
  invented  share of output words absent from input (hallucination proxy)
  latency   ms from run.py
Aggregates: mean dist, mean invented, exact-match rate, latency p50/p95,
plus per-tag breakdown. Usage: ./score.py [cases.jsonl] [results.jsonl]
"""
import json
import os
import sys
from difflib import SequenceMatcher

HERE = os.path.dirname(os.path.abspath(__file__))


def toks(s):
    return (s or "").lower().split()


def pct(vals, q):
    if not vals:
        return 0
    s = sorted(vals)
    return s[min(len(s) - 1, int(q * len(s)))]


def main():
    cases_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        HERE, "cases.jsonl")
    res_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        HERE, "results.jsonl")
    cases = {}
    for line in open(cases_path):
        line = line.strip()
        if line:
            c = json.loads(line)
            cases[c["id"]] = c
    rows = []
    for line in open(res_path):
        line = line.strip()
        if not line:
            continue
        r = json.loads(line)
        c = cases.get(r["id"])
        if c is None:
            continue
        exp, out, inp = toks(c["expected"]), toks(r.get("output", "")), \
            toks(c["input"])
        dist = 1.0 - SequenceMatcher(None, exp, out).ratio() if (
            exp or out) else 0.0
        inset = set(inp)
        inv = [w for w in out if w not in inset]
        invented = len(inv) / max(1, len(out))
        rows.append({"id": r["id"], "tags": c.get("tags", []),
                     "dist": dist, "invented": invented,
                     "lat": r.get("latency_ms", 0),
                     "exact": 1 if exp == out else 0,
                     "finish": r.get("finish_reason", ""),
                     "out": r.get("output", "")})
    if not rows:
        print("no scored rows")
        return
    lats = [r["lat"] for r in rows]
    print("n=%d exact=%.2f mean_dist=%.3f mean_invented=%.3f "
          "p50=%dms p95=%dms length_stops=%d" % (
              len(rows),
              sum(r["exact"] for r in rows) / len(rows),
              sum(r["dist"] for r in rows) / len(rows),
              sum(r["invented"] for r in rows) / len(rows),
              pct(lats, 0.5), pct(lats, 0.95),
              sum(1 for r in rows if r["finish"] == "length")))
    tags = {}
    for r in rows:
        for t in r["tags"]:
            tags.setdefault(t, []).append(r)
    for t in sorted(tags):
        rs = tags[t]
        print("  %-10s n=%-3d exact=%.2f dist=%.3f inv=%.3f p95=%dms" % (
            t, len(rs),
            sum(r["exact"] for r in rs) / len(rs),
            sum(r["dist"] for r in rs) / len(rs),
            sum(r["invented"] for r in rs) / len(rs),
            pct([r["lat"] for r in rs], 0.95)))
    worst = sorted(rows, key=lambda r: -r["dist"])[:5]
    print("worst by dist:")
    for r in worst:
        print("  %s in=%r out=%r" % (
            r["id"], cases[r["id"]]["input"], r["out"]))


main()
