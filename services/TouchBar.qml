import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Touch Bar presses (Macs with tiny-dfr only): each held Touch Bar button
// pushes a bezel-coloured tab out of the bottom screen edge above it, like
// the iPhone volume keys (drawn by core/TouchBarPresses, one per screen).
// scripts/touchbar/presses.py reads tiny-dfr's uinput device and lays the
// buttons out from the active tiny-dfr config, so this side only sees
// "down <id> <x> <w>" / "up <id>" (fractions of the bar length) — no key
// codes. No device / no access (udev rule): the script waits by itself and
// logs the hint once.
Scope {
    id: root

    readonly property var cfg: Config.data.touchBar ?? ({})
    readonly property bool enabled: root.cfg.enabled ?? false
    property bool alive: true

    // pid, bx = centre, bw = width (0..1 of the bar), down, upAt. A
    // released entry stays until its tab has retracted (pruneMs).
    readonly property ListModel presses: ListModel {}

    function indexOf(pid: string): int {
        for (let i = 0; i < root.presses.count; i++)
            if (root.presses.get(i).pid === pid)
                return i;
        return -1;
    }

    function press(pid: string, x: real, w: real): void {
        const i = root.indexOf(pid);
        if (i < 0)
            root.presses.append({ pid, bx: x, bw: w, down: true, upAt: 0 });
        else
            root.presses.set(i, { bx: x, bw: w, down: true, upAt: 0 });
    }

    function release(pid: string): void {
        const i = root.indexOf(pid);
        if (i >= 0)
            root.presses.set(i, { down: false, upAt: Date.now() });
        prune.start();
    }

    function releaseAll(): void {
        for (let i = 0; i < root.presses.count; i++)
            if (root.presses.get(i).down)
                root.presses.set(i, { down: false, upAt: Date.now() });
        prune.start();
    }

    // IPC touchBarDemo: a fake press at x (0..1 of the bar), released after ms.
    property int demoSerial: 0
    function demo(x: real, ms: int): void {
        const pid = `demo:${++root.demoSerial}`;
        root.press(pid, x, 0.06);
        const t = Qt.createQmlObject("import QtQuick; Timer {}", root);
        t.interval = Math.max(1, ms);
        t.triggered.connect(() => { root.release(pid); t.destroy(); });
        t.start();
    }

    onEnabledChanged: if (!root.enabled) root.presses.clear()

    Process {
        id: helper
        running: root.enabled && root.alive
        command: ["python3", `${Quickshell.shellDir}/scripts/touchbar/presses.py`]
        stdout: SplitParser {
            onRead: line => {
                const p = line.split(" ");
                if (p[0] === "down")
                    root.press(p[1], Number(p[2]), Number(p[3]));
                else if (p[0] === "up")
                    root.release(p[1]);
                else if (p[0] === "reset")
                    root.releaseAll();
            }
        }
        stderr: SplitParser {
            onRead: line => console.info(line)
        }
        onExited: code => {
            root.releaseAll();
            if (!root.enabled)
                return;
            console.warn("[TouchBar] presses.py exited:", code);
            root.alive = false;
            respawn.start();
        }
    }
    Timer {
        id: respawn
        interval: 5000
        onTriggered: root.alive = true
    }

    Timer {
        id: prune
        interval: 250
        repeat: true
        onTriggered: {
            const now = Date.now();
            const keep = (root.cfg.minShowMs ?? 0) + (root.cfg.pruneMs ?? 900);
            let pending = false;
            for (let i = root.presses.count - 1; i >= 0; i--) {
                const e = root.presses.get(i);
                if (e.down)
                    continue;
                if (now - e.upAt > keep)
                    root.presses.remove(i);
                else
                    pending = true;
            }
            if (!pending)
                stop();
        }
    }
}
