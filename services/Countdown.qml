import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Countdown timer (the island's "timer": QS card / IPC → modules/timer,
// bar ring = indicators/TimerRing). NOT named Timer: that would shadow
// QtQuick's Timer for every file in this directory.
// phase: idle (setting up) | running | paused | done (rang, waiting for a
// dismiss). Session-only state. `progress` = remaining fraction 1 → 0,
// refreshed often enough that the island's perimeter moves ~0.5 px a step.
Scope {
    id: root

    readonly property var cfg: Config.data.timer
    property string phase: "idle"
    readonly property bool active: root.phase !== "idle"
    readonly property bool running: root.phase === "running"

    // Setup value on the ruler (minutes, 0..maxMinutes), kept for the
    // session: the module reopens on the last choice.
    property int setupMinutes: root.cfg.defaultMinutes ?? 10
    // The ruler breaks the binding above: a new default (settings window)
    // still lands while no timer is set.
    readonly property int defaultMinutes: root.cfg.defaultMinutes ?? 10
    onDefaultMinutesChanged: if (!root.active) root.setupMinutes = root.defaultMinutes

    property real totalMs: 0
    property real endAt: 0          // epoch ms while running
    property real leftMs: 0         // remaining while paused / done
    property real now: Date.now()

    readonly property real remainingMs: root.running ? Math.max(0, root.endAt - root.now) : root.leftMs
    readonly property real progress: root.totalMs > 0 ? Math.max(0, Math.min(1, root.remainingMs / root.totalMs)) : 0
    // Whole seconds, rounded UP (a timer shows 0:00 only when it rang).
    readonly property int remainingSec: Math.ceil(root.remainingMs / 1000)
    readonly property string remainingText: root.format(root.remainingSec)
    // When it rings (bell line); paused = if resumed now.
    readonly property string endText: {
        const at = new Date((root.running ? root.endAt : root.now + root.leftMs));
        return Qt.formatTime(at, "HH:mm");
    }

    signal finished

    // "M:SS", "H:MM:SS" from an hour on.
    function format(sec: int): string {
        sec = Math.max(0, sec);
        const h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60), s = sec % 60;
        const ss = (s < 10 ? "0" : "") + s;
        return h > 0 ? `${h}:${m < 10 ? "0" : ""}${m}:${ss}` : `${m}:${ss}`;
    }

    function start(minutes: int): void {
        const m = Math.max(0, Math.min(root.cfg.maxMinutes ?? 120, minutes));
        if (m <= 0)
            return;
        root.setupMinutes = m;
        root.stopAlarm();
        root.totalMs = m * 60000;
        root.now = Date.now();
        root.endAt = root.now + root.totalMs;
        root.leftMs = root.totalMs;
        root.phase = "running";
    }
    function pause(): void {
        if (!root.running)
            return;
        root.now = Date.now();
        root.leftMs = Math.max(0, root.endAt - root.now);
        root.phase = "paused";
    }
    function resume(): void {
        if (root.phase !== "paused")
            return;
        root.now = Date.now();
        root.endAt = root.now + root.leftMs;
        root.phase = "running";
    }
    function toggle(): void {
        if (root.running)
            root.pause();
        else if (root.phase === "paused")
            root.resume();
        else if (root.phase === "done")
            root.start(root.setupMinutes);
    }
    // Cancel / dismiss: back to setting up.
    function cancel(): void {
        root.stopAlarm();
        root.phase = "idle";
        root.leftMs = 0;
        root.totalMs = 0;
    }

    // Refresh rate: a perimeter step of ~0.5 px (perimeterPx long), between
    // 16 ms and 1 s — a 2 h timer must not repaint every frame for hours.
    Timer {
        running: root.running
        repeat: true
        interval: Math.max(16, Math.min(1000, root.totalMs / Math.max(1, (root.cfg.perimeterPx ?? 900) * 2)))
        onTriggered: {
            root.now = Date.now();
            if (root.endAt - root.now <= 0) {
                root.leftMs = 0;
                root.phase = "done";
                root.ring();
                root.finished();
            }
        }
    }
    // While paused the end time ("rings at") drifts with the clock.
    Timer {
        running: root.phase === "paused"
        repeat: true
        interval: 1000
        onTriggered: root.now = Date.now()
    }

    // ---- alarm sound: `alarmSound` every alarmEveryMs, at most alarmMaxSec.

    property real alarmUntil: 0
    function ring(): void {
        root.alarmUntil = Date.now() + (root.cfg.alarmMaxSec ?? 60) * 1000;
        root.playOnce();
        alarmLoop.restart();
    }
    function stopAlarm(): void {
        alarmLoop.stop();
        root.alarmUntil = 0;
        if (sound.running)
            sound.signal(15);
    }
    function playOnce(): void {
        const file = root.cfg.alarmSound ?? "";
        if (file === "" || sound.running)
            return;
        sound.command = ["pw-play", file];
        sound.running = true;
    }
    Timer {
        id: alarmLoop
        repeat: true
        interval: root.cfg.alarmEveryMs ?? 2500
        onTriggered: {
            if (root.phase !== "done" || Date.now() > root.alarmUntil) {
                stop();
                return;
            }
            root.playOnce();
        }
    }
    Process {
        id: sound
    }
}
