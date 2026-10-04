import QtQuick
import Quickshell
import Quickshell.Io
import "../../config"

// Niri backend. State via `niri msg -j windows/workspaces` polling; builds
// both the global view and a per-output map (perScreen) so multi-monitor
// islands see their own fullscreen/workspace state. Recording is NOT handled
// here: the facade delegates it to the Recorder service.
Item {
    id: root

    property bool fullscreen: false
    property int workspace: 1
    property int workspaceCount: 1
    // { "<output>": { fullscreen: bool, workspace: int, workspaceCount: int } }
    property var perScreen: ({})
    property string focusedOutput: ""
    // Only the detected backend polls its compositor.
    property bool active: false
    property var windows: []
    property var workspaces: []
    property var outputs: ({})

    function grabFocus(): void {} // niri: keyboard focus is layershell-driven
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

    // Windows of the output's active workspace, from the last poll:
    // tile_pos_in_workspace_view + window_offset_in_tile (output-local
    // logical). Windows without a view position (offscreen) are skipped.
    function windowRects(name: string): var {
        const ws = (root.workspaces ?? []).find(w => w.output === name && w.is_active);
        if (!ws || !Array.isArray(root.windows))
            return [];
        return root.windows.filter(w => w.workspace_id === ws.id && w.layout?.tile_pos_in_workspace_view).map(w => {
            const pos = w.layout.tile_pos_in_workspace_view;
            const off = w.layout.window_offset_in_tile ?? [0, 0];
            const size = w.layout.window_size ?? [0, 0];
            return {
                x: pos[0] + off[0],
                y: pos[1] + off[1],
                width: size[0],
                height: size[1],
                focused: w.is_focused === true,
                title: w.title ?? ""
            };
        }).sort((a, b) => (b.focused ? 1 : 0) - (a.focused ? 1 : 0));
    }

    function outputsMap(raw: var): var {
        const m = {};
        if (Array.isArray(raw)) {
            for (const o of raw)
                m[o.name ?? ""] = o;
        } else if (raw) {
            for (const k in raw)
                m[raw[k].name ?? k] = raw[k];
        }
        return m;
    }

    // Fullscreen detection. Newer niri reports is_fullscreen on the window;
    // this niri (26.04) does not, so a window covering the whole output
    // (window_size == logical output size) counts as fullscreen too.
    function isFullscreenWindow(win: var, outName: string): bool {
        if (!win)
            return false;
        if (win.is_fullscreen === true)
            return true;
        const size = win.layout?.window_size ?? null;
        const logical = root.outputs[outName]?.logical ?? null;
        if (!size || !logical)
            return false;
        return size[0] >= logical.width - 2 && size[1] >= logical.height - 2;
    }

    function recompute(): void {
        const ws = root.workspaces;
        const wins = root.windows;
        if (!Array.isArray(ws) || !Array.isArray(wins))
            return;

        // Global view (focused workspace / focused window).
        const focusedWs = ws.find(w => w.is_focused);
        root.workspace = focusedWs?.idx ?? 1;
        root.focusedOutput = focusedWs?.output ?? "";
        root.workspaceCount = ws.length;
        const focusedWin = wins.find(w => w.is_focused);
        const focusedOut = focusedWin
            ? (ws.find(x => x.id === focusedWin.workspace_id)?.output ?? "")
            : "";
        root.fullscreen = root.isFullscreenWindow(focusedWin, focusedOut);

        // Per-output view: active workspace per output; fullscreen if the
        // active window on that output's active workspace covers it.
        const byOutput = {};
        for (const w of ws) {
            const out = w.output ?? "";
            if (!byOutput[out])
                byOutput[out] = { fullscreen: false, workspace: w.idx ?? 1, workspaceCount: 0 };
            byOutput[out].workspaceCount += 1;
            if (w.is_active) {
                byOutput[out].workspace = w.idx ?? 1;
                if (w.active_window_id != null) {
                    const win = wins.find(x => x.id === w.active_window_id);
                    if (win && root.isFullscreenWindow(win, out))
                        byOutput[out].fullscreen = true;
                }
            }
        }
        // The globally focused window always counts for its own output too:
        // niri's per-workspace active_window_id can lag behind actual focus
        // (e.g. floating windows), so the focused window is authoritative.
        if (focusedWin && focusedOut !== "" && byOutput[focusedOut]
            && root.isFullscreenWindow(focusedWin, focusedOut))
            byOutput[focusedOut].fullscreen = true;
        root.perScreen = byOutput;
    }

    Process { id: spawnProc }
    Process { id: shotProc }

    Process {
        id: windowsProc
        command: ["niri", "msg", "-j", "windows"]
        stdout: StdioCollector {
            id: windowsOut
            onStreamFinished: {
                try {
                    root.windows = JSON.parse(windowsOut.text);
                } catch (e) {}
                root.recompute();
            }
        }
    }

    Process {
        id: workspaceProc
        command: ["niri", "msg", "-j", "workspaces"]
        stdout: StdioCollector {
            id: workspaceOut
            onStreamFinished: {
                try {
                    root.workspaces = JSON.parse(workspaceOut.text);
                } catch (e) {}
                root.recompute();
            }
        }
    }

    Process {
        id: outputsProc
        command: ["niri", "msg", "-j", "outputs"]
        stdout: StdioCollector {
            id: outputsOut
            onStreamFinished: {
                try {
                    root.outputs = root.outputsMap(JSON.parse(outputsOut.text));
                } catch (e) {}
                root.recompute();
            }
        }
    }

    Timer {
        interval: Config.data.compositor.pollMs
        running: root.active
        repeat: true
        onTriggered: {
            windowsProc.running = true;
            workspaceProc.running = true;
            outputsProc.running = true;
        }
    }
}
