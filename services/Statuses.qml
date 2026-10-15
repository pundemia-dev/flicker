import QtQuick
import Quickshell
import "../config"

// Status indicators: long processes (timer, transcription, Shazam
// listening, recording being saved, LocalSend, wallpaper indexing). Unlike
// events (inform once, then leave) a status stays for as long as its
// process runs. ONE is shown at a time (iOS): the highest priority, or the
// one the user swiped to (`pinned`, until it ends). Drawn as a ring in the
// drop right of the island (core/StatusDrop); while the status's own event
// shows (event `status: key`) the ring sits inline at the island's right end.
//
// Status = { key, priority, color, progress, open }:
//   color     Theme colour NAME, or a function returning one (live)
//   progress  0..1 remaining/done, a function (live) or null / a function
//             returning null = indeterminate (spinning arc)
//   open      what a tap on the drop does (Island.openStatus): "timer",
//             "transcript", "stash" or "" (nothing)
// post() with the same key replaces in place (keeps its place in the order).
Scope {
    id: root

    readonly property var cfg: Config.data.status
    readonly property bool enabled: root.cfg?.enabled ?? true
    property var items: []
    // Key the user swiped to ("" = follow priority).
    property string pinned: ""
    // Direction of the last switch (+1 / -1): the ring spins that way.
    property int lastDir: 1

    readonly property var ordered: root.items.slice().sort((a, b) => ((b.priority ?? 0) - (a.priority ?? 0)) || (a.since - b.since))
    readonly property var current: {
        if (!root.enabled || root.ordered.length === 0)
            return null;
        return root.ordered.find(s => s.key === root.pinned) ?? root.ordered[0];
    }
    readonly property bool active: root.current !== null

    function find(key: string): var {
        return root.items.find(s => s.key === key) ?? null;
    }

    function post(st: var): void {
        if (!st || !st.key)
            return;
        const old = root.find(st.key);
        const entry = Object.assign({}, st, { since: old ? old.since : Date.now() });
        root.items = old ? root.items.map(s => s.key === st.key ? entry : s) : [...root.items, entry];
    }

    function cancel(key: string): void {
        if (!root.find(key))
            return;
        if (root.pinned === key)
            root.pinned = "";
        root.items = root.items.filter(s => s.key !== key);
    }

    // Swipe on the drop: the next (dir +1) / previous status in the order.
    function cycle(dir: int): void {
        const list = root.ordered;
        if (list.length < 2 || !root.current)
            return;
        const i = list.findIndex(s => s.key === root.current.key);
        root.lastDir = dir >= 0 ? 1 : -1;
        root.pinned = list[(i + root.lastDir + list.length) % list.length].key;
    }

    // Live readers (functions are called inside the caller's binding).
    function progressOf(st: var): var {
        const p = typeof st?.progress === "function" ? st.progress() : st?.progress;
        return (p === null || p === undefined) ? null : Math.max(0, Math.min(1, p));
    }
    function colorOf(st: var): string {
        const c = typeof st?.color === "function" ? st.color() : st?.color;
        return `${c ?? "islandFg"}`;
    }
}
