.pragma library

// Removal motion for a rebuild under the same query (a file hidden,
// deleted, renamed): FLIP the surviving cards and dissolve the gone ones.
//   o: { oldIdx: {path: i}, oldPos, idx: {path: i} (new), target (new
//        centre index), list (new entries), oldList, reach (cards either
//        side worth animating), renames: {newPath: oldPath} }
// Returns { flip: {path: d offset to spring back to 0}, instant: {path:
// true} (every survivor: no rise-in — the Repeater RECREATES moved
// delegates, a fresh rise-in blanked them for ~1 s), leaving: [{ entry, d }] }.
function compute(o) {
    const flip = {}, instant = {}, leaving = [];
    const renamedFrom = {};
    for (const n in o.renames)
        if (o.idx[n] !== undefined)
            renamedFrom[o.renames[n]] = n;

    const lo = Math.max(0, o.target - o.reach), hi = Math.min(o.list.length - 1, o.target + o.reach);
    for (let i = lo; i <= hi; i++) {
        const path = o.list[i].path;
        const old = o.oldIdx[path] ?? o.oldIdx[o.renames[path]];
        if (old === undefined)
            continue;
        const delta = (old - o.oldPos) - (i - o.target);
        if (Math.abs(delta) > 0.001)
            flip[path] = delta;
        instant[path] = true;
    }

    const olo = Math.max(0, Math.round(o.oldPos) - o.reach);
    const ohi = Math.min(o.oldList.length - 1, Math.round(o.oldPos) + o.reach);
    for (let i = olo; i <= ohi; i++) {
        const e = o.oldList[i];
        if (o.idx[e.path] === undefined && renamedFrom[e.path] === undefined)
            leaving.push({ entry: e, d: i - o.oldPos });
    }
    return { flip: flip, instant: instant, leaving: leaving };
}
