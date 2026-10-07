.pragma library
.import "../../fuzzysort.js" as Fuzzy

// Carousel search: an optional one-letter prefix + fuzzy text.
//   "v " videos, "g " GIFs, "i " images, "f " favourites, "h " history
//   (newest first); the rest is fuzzy matched on the file name.
const PREFIXES = { v: "video", g: "gif", i: "image", f: "fav", h: "history" };

function parse(q) {
    const m = /^([vgifh])(?:\s+|$)(.*)$/.exec(q || "");
    return {
        filter: m ? PREFIXES[m[1]] : "",
        query: (m ? m[2] : q || "").trim()
    };
}

// Hidden files (".name"): "normal" leaves them out, "include" shows them
// among the rest, "only" shows nothing else (Ctrl+H cycles).
var VISIBILITY = ["normal", "include", "only"];

// files: service entries (sorted); ctx: { favourites: {path: true},
// history: [path, ...], visibility }. Returns the visible entries.
function apply(files, f, ctx) {
    const vis = ctx.visibility || "normal";
    let list = vis === "include" ? files : files.filter(e => e.hidden === (vis === "only"));
    if (f.filter === "fav") {
        list = list.filter(e => ctx.favourites[e.path]);
    } else if (f.filter === "history") {
        const byPath = {};
        for (const e of list)
            byPath[e.path] = e;
        list = ctx.history.map(p => byPath[p]).filter(e => !!e);
    } else if (f.filter) {
        list = list.filter(e => e.type === f.filter);
    }
    if (f.query)
        list = rank(Fuzzy.go(f.query, list, { key: "name" }), list);
    return list;
}

let rankNonce = 0;

// fuzzysort ranks through a heap: EQUAL scores come out in an input-
// dependent order, so removing one card reshuffled its ties (cards far
// from the gap swapped). Order by score, ties in list order — linear:
// stamp each hit, then bucket the input list by score (a comparator sort
// with Map lookups took 1.3 s for 3300 hits in QV4).
function rank(results, list) {
    const nonce = ++rankNonce;
    for (const r of results) {
        r.obj._wfNonce = nonce;
        r.obj._wfScore = r._score;
    }
    const buckets = {};
    const scores = [];
    for (const e of list) {
        if (e._wfNonce !== nonce)
            continue;
        const b = buckets[e._wfScore];
        if (b) {
            b.push(e);
        } else {
            buckets[e._wfScore] = [e];
            scores.push(e._wfScore);
        }
    }
    scores.sort((a, b) => b - a);
    let out = [];
    for (const sc of scores)
        out = out.concat(buckets[sc]);
    return out;
}

// Same query, files changed (hide/unhide, delete, a rescan): keep the
// current order instead of re-running the fuzzy search. `renames`
// (newPath -> oldPath) puts a renamed card in its old slot. A file that
// was not among the previous files (prevFiles: {path: true}) may match
// the query somewhere → returns null (do a real search).
function refine(prev, files, prevFiles, f, ctx, renames) {
    const vis = ctx.visibility || "normal";
    const byPath = {};
    for (const e of files) {
        if (!prevFiles[e.path] && renames[e.path] === undefined)
            return null;
        byPath[e.path] = e;
    }
    const fromOld = {};
    for (const n in renames)
        fromOld[renames[n]] = n;
    const out = [];
    for (const e of prev) {
        const n = byPath[e.path] ?? (fromOld[e.path] !== undefined ? byPath[fromOld[e.path]] : undefined);
        if (!n)
            continue;
        if (vis !== "include" && n.hidden !== (vis === "only"))
            continue;
        if (f.filter === "fav" && !ctx.favourites[n.path])
            continue;
        out.push(n);
    }
    return out;
}
