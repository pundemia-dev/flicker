import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Measured caret offsets (child of services/Caret). text-input reports the
// caret in SURFACE coords; client-side margins (GTK shadow / resize border,
// different per window type: zenity text window 10/20, zenity dialog 20/20)
// put the surface origin up-left of the window geometry the IPC reports, and
// nothing exposes them. `scripts/keyboard/calibrate.py` measures it from the
// blinking caret: a few driftwm `screenshot window` captures (in memory) ~1.4 s
// apart, their difference = the caret, offset = reported − found (centres).
// Run once per window, `calibrateDelayMs` after the caret settles (typing
// keeps carets solid); a result counts only if the rect did not move
// meanwhile. The window's offset is also the starting guess for new windows
// of the same app. Session-only. driftwm only (niri has no window capture to
// stdout) — elsewhere offsets stay 0 unless `keyboard.caretOffsets` says.
Scope {
    id: root
    required property var compositor

    readonly property var cfg: Config.data.keyboard ?? ({})
    readonly property bool enabled: (cfg.calibrate ?? true) && (root.compositor?.detect?.backendName ?? "") === "drift"

    // "id:<window id>" / "app:<app_id>" -> [dx, dy]
    property var offsets: ({})
    // window id -> failed attempts (reset when a field activates again)
    property var tries: ({})

    function offsetFor(win: var): var {
        if (!win)
            return [0, 0];
        return (root.cfg.caretOffsets ?? ({}))[win.appId] ?? root.offsets["id:" + win.id] ?? root.offsets["app:" + win.appId] ?? [0, 0];
    }
    function known(win: var): bool {
        return !!win && (root.offsets["id:" + win.id] !== undefined || (root.cfg.caretOffsets ?? ({}))[win.appId] !== undefined);
    }

    // The caret went somewhere (or a field activated): measure once it rests.
    function note(win: var, rect: var, fresh: bool): void {
        if (!root.enabled || !win || !rect || win.id === undefined || root.known(win))
            return;
        if (fresh && root.tries[win.id]) {
            const t = Object.assign({}, root.tries);
            delete t[win.id];
            root.tries = t;
        }
        pendingWin = win;
        pendingRect = rect;
        settle.restart();
    }

    property var pendingWin: null
    property var pendingRect: null
    property var runWin: null
    property var runRect: null
    // Rect the caret service holds now (to reject a result after a move).
    property var currentRect: null

    Timer {
        id: settle
        interval: root.cfg.calibrateDelayMs ?? 400
        onTriggered: {
            const win = root.pendingWin, r = root.pendingRect;
            if (!win || !r || probe.running || root.known(win))
                return;
            if ((root.tries[win.id] ?? 0) >= (root.cfg.calibrateAttempts ?? 4))
                return;
            root.runWin = win;
            root.runRect = r.slice();
            probe.command = ["python3", `${Quickshell.shellDir}/scripts/keyboard/calibrate.py`, String(win.id),
                String(r[0]), String(r[1]), String(r[2]), String(r[3]),
                String(root.cfg.calibrateFrames ?? 7), String((root.cfg.calibrateIntervalMs ?? 200) / 1000)];
            probe.running = true;
        }
    }

    Process {
        id: probe
        stdout: StdioCollector {
            onStreamFinished: {
                let res = null;
                try {
                    res = JSON.parse(text ?? "");
                } catch (e) {}
                const win = root.runWin, r = root.runRect, now = root.currentRect;
                const still = now && r && now.length === 4 && now.every((v, i) => v === r[i]);
                const lim = root.cfg.calibrateMaxPx ?? 80;
                if (win && still && res && res.dx !== undefined && Math.abs(res.dx) <= lim && Math.abs(res.dy) <= lim) {
                    const o = Object.assign({}, root.offsets);
                    o["id:" + win.id] = [res.dx, res.dy];
                    o["app:" + win.appId] = [res.dx, res.dy];
                    root.offsets = o;
                    console.log("[caret] offset", win.appId, "#" + win.id, res.dx, res.dy);
                } else if (win) {
                    const t = Object.assign({}, root.tries);
                    t[win.id] = (t[win.id] ?? 0) + 1;
                    root.tries = t;
                    // A move during the run: measure again once it rests.
                    if (!still && now)
                        root.note(win, now, false);
                }
                root.runWin = null;
            }
        }
    }
}
