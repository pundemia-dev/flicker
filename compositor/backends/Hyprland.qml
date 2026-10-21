import QtQuick
import Quickshell
import Quickshell.Io
import "../../config"

// Hyprland backend. State = `hyprctl -j monitors / workspaces / clients`
// snapshots, refreshed on every line of the event socket (.socket2.sock,
// debounced) plus a slow fallback poll. Monitor x/y and client at/size are
// logical layout coords; monitor width/height are physical (÷ scale).
// Fullscreen = a client on the monitor's active workspace with fullscreen
// mode 2/3 (1 = maximized, keeps the bar's reserved area) or legacy `true`.
// Recording is NOT handled here: the facade delegates it to the Recorder.
Item {
    id: root

    property bool fullscreen: false
    property int workspace: 1
    property int workspaceCount: 1
    // { "<output>": { fullscreen: bool, workspace: int, workspaceCount: int } }
    property var perScreen: ({})
    property string focusedOutput: ""
    // Only the detected backend talks to its compositor.
    property bool active: false
    property var monitors: []
    property var workspaces: []
    property var windows: []

    readonly property string signature: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? ""
    readonly property string eventSocket: {
        const run = Quickshell.env("XDG_RUNTIME_DIR") ?? "";
        return root.signature.length > 0 ? `${run}/hypr/${root.signature}/.socket2.sock` : "";
    }

    function grabFocus(): void {} // keyboard focus is layershell-driven
    function releaseFocus(): void {}

    function spawn(cmd: string): void {
        spawnProc.command = ["bash", "-lc", cmd];
        spawnProc.running = true;
    }

    function screenshot(region: string): void {
        shotProc.command = region.length > 0
            ? ["bash", "-lc", `grim -g '${region}' ${Config.data.capture.screenshotFile}`]
            : ["bash", "-lc", `grim ${Config.data.capture.screenshotFile}`];
        shotProc.running = true;
    }

    function isFullscreen(c: var): bool {
        const f = c?.fullscreen;
        return f === true || (typeof f === "number" && f >= 2);
    }

    // Workspaces visible on a monitor: the active one plus an open special
    // workspace (scratchpad, drawn on top).
    function visibleWorkspaceIds(mon: var): var {
        const ids = [];
        if (mon?.activeWorkspace?.id != null)
            ids.push(mon.activeWorkspace.id);
        if (mon?.specialWorkspace?.id)
            ids.push(mon.specialWorkspace.id);
        return ids;
    }

    // Mapped, visible clients on the output, output-local logical rects.
    // Topmost first: focused, special workspace, floating/pinned, then
    // tiled — each by focus history (0 = most recent).
    function windowRects(name: string): var {
        const mon = (root.monitors ?? []).find(m => m.name === name);
        if (!mon || !Array.isArray(root.windows))
            return [];
        const ids = root.visibleWorkspaceIds(mon);
        const special = mon.specialWorkspace?.id ?? 0;
        const rank = c => (c.focusHistoryID === 0 ? 0 : 8) + (special && c.workspace?.id === special ? 0 : 4) + (c.floating || c.pinned ? 0 : 2);
        return root.windows.filter(c => c.mapped !== false && c.hidden !== true && c.at && c.size
                && (ids.indexOf(c.workspace?.id) !== -1 || (c.pinned && c.monitor === mon.id)))
            .sort((a, b) => rank(a) - rank(b) || (a.focusHistoryID ?? 99) - (b.focusHistoryID ?? 99))
            .map(c => ({
                    x: c.at[0] - (mon.x ?? 0),
                    y: c.at[1] - (mon.y ?? 0),
                    width: c.size[0],
                    height: c.size[1],
                    focused: c.focusHistoryID === 0,
                    title: c.title ?? "",
                    appId: c.class ?? "",
                    id: c.address,
                    zoom: 1
                }));
    }

    function recompute(): void {
        const mons = root.monitors;
        const ws = root.workspaces;
        const wins = root.windows;
        if (!Array.isArray(mons) || !Array.isArray(ws) || !Array.isArray(wins))
            return;

        const byOutput = {};
        for (const m of mons) {
            const ids = root.visibleWorkspaceIds(m);
            byOutput[m.name ?? ""] = {
                fullscreen: wins.some(c => ids.indexOf(c.workspace?.id) !== -1 && c.mapped !== false && root.isFullscreen(c)),
                workspace: m.activeWorkspace?.id ?? 1,
                // Regular workspaces only (special ones have negative ids).
                workspaceCount: Math.max(1, ws.filter(w => w.monitor === m.name && (w.id ?? 0) > 0).length)
            };
        }
        root.perScreen = byOutput;

        const focused = mons.find(m => m.focused) ?? mons[0] ?? null;
        root.focusedOutput = focused?.name ?? "";
        root.workspace = focused?.activeWorkspace?.id ?? 1;
        root.workspaceCount = Math.max(1, ws.filter(w => (w.id ?? 0) > 0).length);
        root.fullscreen = focused ? (byOutput[focused.name]?.fullscreen ?? false) : false;
    }

    function refresh(): void {
        monitorsProc.running = true;
        workspacesProc.running = true;
        clientsProc.running = true;
    }

    onActiveChanged: if (active) refresh()
    Component.onCompleted: if (active) refresh()

    Process { id: spawnProc }
    Process { id: shotProc }

    Process {
        id: monitorsProc
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.monitors = JSON.parse(text);
                } catch (e) {}
                root.recompute();
            }
        }
    }

    Process {
        id: workspacesProc
        command: ["hyprctl", "-j", "workspaces"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.workspaces = JSON.parse(text);
                } catch (e) {}
                root.recompute();
            }
        }
    }

    Process {
        id: clientsProc
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.windows = JSON.parse(text);
                } catch (e) {}
                root.recompute();
            }
        }
    }

    // Event socket: any event (workspace, fullscreen, openwindow, movewindow,
    // activewindowv2, monitoradded, …) schedules one refresh. Window geometry
    // changes (drag/resize) emit no event — the fallback poll covers those.
    Socket {
        id: events
        path: root.eventSocket
        connected: root.active && root.eventSocket.length > 0
        parser: SplitParser {
            onRead: line => {
                const ev = (line ?? "").split(">>")[0];
                if (ev.length > 0 && ev !== "activelayout")
                    debounce.restart();
            }
        }
        onConnectedChanged: {
            if (!connected && root.active)
                reconnect.restart();
        }
    }

    Timer {
        id: debounce
        interval: 60
        onTriggered: root.refresh()
    }

    Timer {
        id: reconnect
        interval: Config.data.compositor.pollMs
        onTriggered: {
            if (root.active && !events.connected && root.eventSocket.length > 0)
                events.connected = true;
        }
    }

    Timer {
        interval: Config.data.compositor.pollMs * 2
        running: root.active
        repeat: true
        onTriggered: root.refresh()
    }
}
