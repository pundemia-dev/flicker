import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Feeds cliphist: `wl-paste --type text|image --watch cliphist store` (the
// cliphist README pair; noctalia's old QML shell spawned the same, end-4
// pings its service after every store). niri spawns its own watcher, driftwm
// does not — so `watch: "auto"` starts ours unless an external one already
// runs (checked once at start). Ours run as argv[0] `pillshell-clipwatch`, so
// the check never sees them (hot reload: the old instance's are still alive).
// Every store prints a line → `revision` bumps → an open clipboard plugin
// re-lists (image copies raise no clipboardTextChanged).
Scope {
    id: root

    readonly property var cfg: Config.data.launcher.clipboard
    readonly property var mode: root.cfg?.watch ?? "auto"
    readonly property int restartMs: root.cfg?.watchRestartMs ?? 2000

    // "unknown" until the probe ran, then "external" | "own" | "off".
    property string source: "unknown"
    property int revision: 0
    readonly property bool running: textWatch.running || imageWatch.running

    function watchCommand(type: string): var {
        return ["bash", "-c", `exec -a pillshell-clipwatch wl-paste --type ${type} --watch sh -c 'cliphist store; echo stored'`];
    }

    function decide(): void {
        if (root.mode === false || root.mode === "off") {
            root.source = "off";
        } else if (root.mode === true || root.mode === "on") {
            root.source = "own";
        } else {
            probe.running = true;
            return;
        }
        root.apply();
    }

    function apply(): void {
        const own = root.source === "own";
        textWatch.running = own;
        imageWatch.running = own;
    }

    onModeChanged: decide()
    Component.onCompleted: decide()

    // Exit 0 = an external watcher feeds cliphist already.
    Process {
        id: probe
        command: ["pgrep", "-f", "(^|/)wl-paste .*--watch.*cliphist +store"]
        onExited: code => {
            root.source = code === 0 ? "external" : "own";
            console.info("[ClipboardWatch]", root.source === "own" ? "starting own wl-paste watchers" : "external watcher found");
            root.apply();
        }
    }

    function watcherExited(type: string, code: int): void {
        if (root.source !== "own")
            return;
        console.warn("[ClipboardWatch] wl-paste", type, "exited:", code, "— restarting");
        restart.restart();
    }

    Process {
        id: textWatch
        command: root.watchCommand("text")
        stdout: SplitParser {
            onRead: root.revision++
        }
        onExited: code => root.watcherExited("text", code)
    }
    Process {
        id: imageWatch
        command: root.watchCommand("image")
        stdout: SplitParser {
            onRead: root.revision++
        }
        onExited: code => root.watcherExited("image", code)
    }

    Timer {
        id: restart
        interval: root.restartMs
        onTriggered: root.apply()
    }
}
