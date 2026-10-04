import QtQuick
import Quickshell.Io
import "../../config"

// DriftWM backend. State comes from `driftwm msg subscribe --json`: one
// `{"State": {...}}` snapshot per line on every compositor state change
// (plus a one-shot `driftwm msg --json state` for the initial value).
// Fullscreen is the top-level `fullscreen: [{id, output, app_id, title}]`
// list — NOT window `mode` ("Fit" is fit-to-viewport, not fullscreen).
// DriftWM is an infinite canvas: no workspaces, so workspace stays 1.
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

    function runRegionCapture(mode: string): void {
        const file = mode === "ai" ? Config.data.capture.aiFile : Config.data.capture.screenshotFile;
        regionProc.command = ["bash", "-lc", `grim -g "$(slurp)" ${file}`];
        regionProc.running = true;
    }

    // Window size >= output size (±2px) at zoom 1, centred on the output's
    // camera (position = visible frame centre, camera = viewport centre),
    // i.e. actually on screen rather than scrolled away on the canvas.
    function coversOutput(win: var, out: var): bool {
        const size = win?.size ?? null;
        const osize = out?.size ?? null;
        const pos = win?.position ?? null;
        const cam = out?.camera ?? null;
        if (!size || !osize || !pos || !cam)
            return false;
        if (Math.abs((out.zoom ?? 1) - 1) > 0.01)
            return false;
        return size[0] >= osize[0] - 2 && size[1] >= osize[1] - 2
            && Math.abs(pos[0] - cam[0]) <= 2 && Math.abs(pos[1] - cam[1]) <= 2;
    }

    function apply(st: var): void {
        if (!st)
            return;
        const outputs = Array.isArray(st.outputs) ? st.outputs : [];
        const fsOutputs = (Array.isArray(st.fullscreen) ? st.fullscreen : []).map(f => f?.output ?? "");
        const byOutput = {};
        for (const o of outputs) {
            const name = o?.name ?? "";
            byOutput[name] = {
                fullscreen: fsOutputs.indexOf(name) !== -1,
                workspace: 1,
                workspaceCount: 1
            };
        }
        const active = outputs.find(o => o?.active) ?? outputs[0] ?? null;
        root.focusedOutput = active?.name ?? "";
        // fit-window (mode "Fit") is driftwm's maximize, not fullscreen, but
        // a focused window covering the whole active output counts too (same
        // rule as the niri backend): the island must not sit over it.
        const focused = (Array.isArray(st.windows) ? st.windows : []).find(w => w?.is_focused) ?? null;
        if (active && root.coversOutput(focused, active) && fsOutputs.indexOf(active.name) === -1) {
            fsOutputs.push(active.name);
            if (byOutput[active.name])
                byOutput[active.name].fullscreen = true;
        }
        root.fullscreen = active ? fsOutputs.indexOf(active.name) !== -1 : fsOutputs.length > 0;
        root.perScreen = byOutput;
    }

    Process { id: spawnProc }
    Process { id: shotProc }
    Process { id: regionProc }

    Process {
        id: initProc
        running: root.active
        command: ["driftwm", "msg", "--json", "state"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.apply(JSON.parse(text ?? "")?.Ok?.State);
                } catch (e) {
                    console.warn("[Drift] state parse:", e);
                }
            }
        }
    }

    Process {
        id: subProc
        running: root.active
        command: ["driftwm", "msg", "subscribe", "--json"]
        stdout: SplitParser {
            onRead: line => {
                let st = null;
                try {
                    const msg = JSON.parse(line ?? "");
                    st = msg?.State ?? msg?.Ok?.State ?? null;
                } catch (e) {
                    return;
                }
                root.apply(st);
            }
        }
        onExited: code => {
            if (!root.active)
                return;
            console.warn("[Drift] subscribe exited", code, "— retrying");
            retryTimer.restart();
        }
    }

    Timer {
        id: retryTimer
        interval: Config.data.compositor.pollMs
        onTriggered: {
            initProc.running = true;
            subProc.running = true;
        }
    }
}
