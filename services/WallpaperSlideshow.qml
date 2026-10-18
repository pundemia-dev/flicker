import QtQuick
import Quickshell
import Quickshell.Io
import "../modules/launcher/plugins/wallpapers/WallEntry.js" as WallEntry
import "../modules/launcher/plugins/wallpapers/WallFilter.js" as WallFilter

// Wallpaper slideshow (owned by services/Wallpaper, which persists
// `active` + `spec`): every slideshowIntervalSec the next wallpaper goes
// onto every output with the configured effect. The pool is a carousel
// view — spec { filter, query, visibility } (WallFilter) — resolved
// against a fresh scan at every step, so new files join on their own.
// Order (slideshowOrder): random (never one of the last few shown) or
// sequential (the view's order, after the current one). On battery only
// still images (slideshowStillOnBattery). `hold` (the carousel is open)
// skips steps so it never fights the live preview; `paused` (Low Power
// Mode, services/PowerMode) skips them too. next() still steps on request.
Scope {
    id: root
    required property var wallpaper
    property var cfg: ({})
    property bool discharging: false

    property bool active: false
    property var spec: ({ filter: "", query: "", visibility: "normal" })
    property bool hold: false
    property bool paused: false

    readonly property string scripts: Quickshell.shellDir + "/scripts/wallpapers/"

    signal edited

    function start(spec: var): void {
        root.spec = spec ?? { filter: "", query: "", visibility: "normal" };
        root.active = true;
        stepTimer.restart();
        root.edited();
    }

    function stop(): void {
        root.active = false;
        root.edited();
    }

    function toggle(spec: var): void {
        if (root.active)
            root.stop();
        else
            root.start(spec);
    }

    Timer {
        id: stepTimer
        interval: Math.max(5, root.cfg.slideshowIntervalSec ?? 900) * 1000
        repeat: true
        running: root.active
        onTriggered: if (!root.hold && !root.paused)
            root.next()
    }

    // One step now (IPC wallpaperNext; also works with the slideshow off,
    // over its last pool).
    function next(): void {
        if (scanProc.running)
            return;
        scanProc.command = [root.scripts + "scan.sh", "files", (root.cfg.recursive ?? true) ? "1" : "0"].concat(root.cfg.dirs ?? []);
        scanProc.running = true;
    }

    Process {
        id: scanProc
        stdout: StdioCollector {
            onStreamFinished: root.pick(this.text)
        }
    }

    function pick(text: string): void {
        const files = WallEntry.sort(WallEntry.lines(text).map(l => WallEntry.make(l.path, l.mtimeText, l.sizeText)), root.cfg.sort ?? "name");
        const s = root.spec ?? {};
        let pool = WallFilter.apply(files, { filter: s.filter ?? "", query: s.query ?? "", paths: s.paths ?? [] }, {
            favourites: root.wallpaper.favouriteSet,
            history: root.wallpaper.history,
            visibility: s.visibility ?? "normal"
        });
        if (root.discharging && (root.cfg.slideshowStillOnBattery ?? true))
            pool = pool.filter(e => e.type === "image");
        if (!pool.length)
            return;
        const current = root.wallpaper.history[0] ?? "";
        let path;
        if ((root.cfg.slideshowOrder ?? "random") === "sequential") {
            const i = pool.findIndex(e => e.path === current);
            path = pool[(i + 1) % pool.length].path;
        } else {
            // Not one of the last few shown (up to half the pool).
            const recent = {};
            const n = Math.min(Math.floor(pool.length / 2), root.cfg.slideshowNoRepeat ?? 20);
            for (const p of root.wallpaper.history.slice(0, Math.max(1, n)))
                recent[p] = true;
            const fresh = pool.filter(e => !recent[e.path]);
            const from = fresh.length ? fresh : pool;
            path = from[Math.floor(Math.random() * from.length)].path;
        }
        root.wallpaper.apply(path, root.wallpaper.applyOpts(""));
    }
}
