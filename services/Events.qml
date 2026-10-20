import QtQuick
import Quickshell
import "../config"

// Event indicators ("live activities" in the bar): short-lived facts like
// "charger plugged in" or "headphones connected". ONE at a time, FIFO like
// the notification flow: alone an event stays `showMs`, with more queued
// behind it `showQueuedMs` (an arrival shortens the visible one to that
// budget, counted from when it appeared). Between two events the bar
// collapses for `gapMs`, so the next one blur-fades in on its own.
//
// Event = { key, icon, text, color?, family? }:
//   icon   glyph drawn at the far LEFT of the bar row
//   text   string or function (re-evaluated live inside a binding, e.g.
//          time to full) drawn at the far RIGHT of the row
//   color  icon colour (theme colour, default islandFg)
//   family icon font (default Theme.iconFamily)
//   key    same key = replace in place (current: content updates without
//          restarting its timer; queued: the queued copy is replaced)
//   status key of a running status (services/Statuses): announces it —
//          its ring sits inline at the island's right end while the event
//          shows, then splits off as the status drop
//   hold   stays until replaced by a same-key event without `hold` (its
//          timer starts then) or cancelled — e.g. Shazam "Listening…"
//   tap    function run on a click on the event (it leaves first)
//   open   island module opened on a click (on the clicked island),
//          `openPayload` its payload — e.g. "updates"
Scope {
    id: root

    readonly property var cfg: Config.data.events
    property var queue: []
    // The visible event (null while none / during the gap).
    property var current: null
    property real shownAt: 0

    function post(ev: var): void {
        if (!ev || !(root.cfg?.enabled ?? true))
            return;
        const key = ev.key ?? "";
        if (key !== "" && root.current && (root.current.key ?? "") === key) {
            const wasHeld = !!root.current.hold;
            root.current = ev;
            if (wasHeld && !ev.hold) {
                root.shownAt = Date.now();
                root.arm();
            }
            return;
        }
        const idx = key === "" ? -1 : root.queue.findIndex(e => (e.key ?? "") === key);
        if (idx !== -1) {
            const q = root.queue.slice();
            q[idx] = ev;
            root.queue = q;
            return;
        }
        root.queue = [...root.queue, ev];
        if (root.current)
            root.shorten();
        else if (!gap.running)
            root.next();
    }

    // Drops an event wherever it is (its source went away, e.g. the
    // charger was pulled while "charging" waited in the queue).
    function cancel(key: string): void {
        root.queue = root.queue.filter(e => (e.key ?? "") !== key);
        if (root.current && (root.current.key ?? "") === key)
            root.finish();
    }

    function next(): void {
        if (root.queue.length === 0)
            return;
        root.current = root.queue[0];
        root.queue = root.queue.slice(1);
        root.shownAt = Date.now();
        if (!root.current.hold)
            root.arm();
    }

    function arm(): void {
        life.interval = root.queue.length > 0 ? root.cfg.showQueuedMs : root.cfg.showMs;
        life.restart();
    }

    function shorten(): void {
        if (root.current?.hold)
            return;
        const left = root.cfg.showQueuedMs - (Date.now() - root.shownAt);
        if (left <= 0)
            root.finish();
        else if (left < life.interval - (Date.now() - root.shownAt)) {
            life.interval = left;
            life.restart();
        }
    }

    function finish(): void {
        life.stop();
        root.current = null;
        gap.restart();
    }

    Timer {
        id: life
        onTriggered: root.finish()
    }
    Timer {
        id: gap
        interval: root.cfg.gapMs
        onTriggered: root.next()
    }
}
