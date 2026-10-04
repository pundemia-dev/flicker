import QtQuick
import "backends"

// Compositor facade: everything outside compositor/ talks to this object
// only (spec). Backend-specific state (fullscreen/workspace) comes from the
// detected WM; per-screen state is exposed via perScreen/fullscreenOn/
// workspaceOn. Recording is WM-agnostic (wf-recorder), so the facade keeps
// the spec'd API but delegates to the Recorder service — the single source
// of truth for the recording flag and the wf-recorder process.
Item {
    id: root
    property Detect detect: Detect {}
    property var recorder: null
    property QtObject backend: detect.backendName === "niri" ? niriBackend : (detect.backendName === "hyprland" ? hyprBackend : driftBackend)

    readonly property bool fullscreen: backend.fullscreen ?? false
    readonly property int workspace: backend.workspace ?? 1
    readonly property int workspaceCount: backend.workspaceCount ?? 1
    readonly property var perScreen: backend.perScreen ?? ({})
    // Output name of the focused workspace ("" = unknown): IPC targets the
    // island on this output.
    readonly property string focusedOutput: backend.focusedOutput ?? ""

    function screenInfo(name: string): var {
        return root.perScreen[name] ?? null;
    }

    function fullscreenOn(name: string): bool {
        const s = screenInfo(name);
        return s ? (s.fullscreen ?? false) : fullscreen;
    }

    function workspaceOn(name: string): int {
        const s = screenInfo(name);
        return s ? (s.workspace ?? workspace) : workspace;
    }

    function grabFocus(): void { backend.grabFocus(); }
    function releaseFocus(): void { backend.releaseFocus(); }
    function spawn(cmd: string): void { backend.spawn(cmd); }
    function screenshot(region: string): void { backend.screenshot(region); }
    function runRegionCapture(mode: string): void { backend.runRegionCapture(mode); }
    function startRecording(region: string): void { recorder?.start(region); }
    function stopRecording(): void { recorder?.stop(); }

    Niri { id: niriBackend; active: root.detect.backendName === "niri" }
    Hyprland { id: hyprBackend }
    Drift { id: driftBackend; active: root.detect.backendName === "drift" }
}
