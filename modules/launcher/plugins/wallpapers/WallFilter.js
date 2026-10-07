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
        list = Fuzzy.go(f.query, list, { key: "name" }).map(r => r.obj);
    return list;
}
