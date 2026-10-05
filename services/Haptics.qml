import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Trackpad haptics, hardware-agnostic. The shell only knows three effects
// (click, deep, release) + an intensity 0..1; a BACKEND turns them into
// vibration (scripts/haptics/backends/<name>/backend, contract in
// docs/haptics.md). scripts/haptics/run.py probes the backends
// (Config.haptics.backend: "auto" = first usable in `order`, a name, or a
// path to an own executable) and exec()s the winner, which then reads
// "<effect> <intensity>" lines from this Process's stdin — one long-lived
// process, nothing spawned per tick. No usable backend = exit 3 = silent.
// The haptic is felt only under a finger on the trackpad (keys/IPC events
// just make it tick audibly) — callers pick moments accordingly.
Scope {
    id: root

    readonly property var cfg: Config.data.haptics
    readonly property bool enabled: root.cfg?.enabled ?? false
    property bool alive: true
    property real lastAt: 0
    // Re-probes after "no backend" run --quiet (the hint is logged once).
    property bool rescanning: false
    // Backend choice/options reach the backend only at start: restart it
    // when they change (config hot-reload), without the crash delay.
    readonly property string setupKey: JSON.stringify([root.cfg?.backend, root.cfg?.order, root.cfg?.backendOptions])
    property bool restartQueued: false
    onSetupKeyChanged: {
        if (!helper.running)
            return;
        root.restartQueued = true;
        helper.signal(15);
    }

    function play(effect: string): void {
        const k = root.cfg?.intensity?.[effect];
        if (!root.enabled || !helper.running || !(k > 0))
            return;
        const now = Date.now();
        if (now - root.lastAt < (root.cfg.minIntervalMs ?? 40))
            return;
        root.lastAt = now;
        helper.write(`${effect} ${k}\n`);
    }
    function click(): void { root.play("click"); }
    function deep(): void { root.play("deep"); }
    function release(): void { root.play("release"); }
    function tick(): void { root.play("tick"); }

    Process {
        id: helper
        running: root.enabled && root.alive
        command: ["python3", `${Quickshell.shellDir}/scripts/haptics/run.py`,
            "--backend", root.cfg?.backend ?? "auto",
            "--order", (root.cfg?.order ?? []).join(","),
            "--options", JSON.stringify(root.cfg?.backendOptions ?? {})]
            .concat(root.rescanning ? ["--quiet"] : [])
        stdinEnabled: true
        stderr: SplitParser {
            onRead: line => console.info(line)
        }
        // 3 = no usable backend (no hardware / no access — the hint is in
        // the log): probe again after rescanMs (picks up a freshly
        // installed udev rule; 0 = never). Anything else = died: respawnMs.
        onExited: code => {
            if (!root.enabled)
                return;
            if (root.restartQueued) {
                root.restartQueued = false;
                root.rescanning = false;
                root.alive = false;
                Qt.callLater(() => root.alive = true);
                return;
            }
            root.rescanning = code === 3;
            const wait = code === 3 ? (root.cfg?.rescanMs ?? 30000) : (root.cfg?.respawnMs ?? 5000);
            if (code !== 3)
                console.warn("[Haptics] backend exited:", code);
            root.alive = false;
            if (wait > 0) {
                respawn.interval = wait;
                respawn.start();
            }
        }
    }
    Timer {
        id: respawn
        onTriggered: root.alive = true
    }
}
