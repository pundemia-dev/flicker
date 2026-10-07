import QtQuick
import Quickshell
import "WallrArgs.js" as WallrArgs

// Live preview of the carousel selection on this output (cfg.livePreview):
// once the carousel rests for previewDelayMs the centre card goes onto the
// desktop (short fade, no theming). Leaving without applying (Esc, closing
// the launcher, another plugin) puts `original` back — detached, because
// that also runs from the plugin's onDestruction.
Item {
    id: root
    property var c: ({})
    property var host: null
    property bool active: false
    // Path that would be previewed now (the centre card, "" = none).
    property string target: ""

    property string original: ""
    // Path last put on the desktop ("" = untouched).
    property string previewed: ""
    property bool applied: false

    function reset(): void {
        root.applied = false;
        root.previewed = "";
        root.original = "";
        timer.stop();
    }

    // The carousel came to rest / moved on.
    function rest(): void {
        timer.restart();
    }
    function cancel(): void {
        timer.stop();
    }

    function opts(): var {
        return {
            output: root.host?.screen ?? "",
            effect: "fade",
            durationMs: root.c.previewDurationMs ?? 300,
            theme: "none"
        };
    }

    function set(path: string): void {
        Quickshell.execDetached(WallrArgs.set(path, root.opts(), root.c.mode ?? ""));
    }

    function restore(): void {
        if (root.applied || !root.previewed || !root.original)
            return;
        if (root.previewed !== root.original)
            root.set(root.original);
        root.previewed = "";
    }

    Timer {
        id: timer
        interval: root.c.previewDelayMs ?? 250
        onTriggered: {
            const p = root.target;
            if (!(root.c.livePreview ?? false) || !root.active || !p || !root.host?.screen)
                return;
            if (p === (root.previewed || root.original))
                return;
            root.previewed = p;
            root.set(p);
        }
    }
}
