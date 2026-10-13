import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Text caret position for the keyboard pill. `scripts/keyboard/caret.py`
// is the seat's input method (zwp_input_method_v2, no keyboard grab, one
// never-mapped popup surface): the compositor forwards every text field's
// text-input-v3 cursor rectangle to it, in the FOCUSED SURFACE's local
// coordinates. Global = the focused window's rect (Compositor.windowRects,
// output-local logical, zoom applied) + that rectangle.
// Client-side margins (GTK shadow / resize border) put the surface origin
// up-left of the window geometry the IPC reports: measured per window by
// `calibration` (services/CaretCalibration, from the blinking caret);
// `keyboard.caretOffsets` {app_id: [dx, dy]} overrides. Only ONE input method per seat:
// with fcitx/ibus running the helper exits 3 (`unavailable`) and the pill
// falls back to the mouse pointer.
Scope {
    id: root
    required property var compositor
    // IslandRegistry: while an island holds the keyboard the caret is in a
    // shell field (its rect is relative to the island surface) — ignored.
    property var registry: null

    readonly property var cfg: Config.data.keyboard ?? ({})
    readonly property bool wanted: (cfg.enabled ?? true) && (cfg.followCaret ?? true)

    // A text field has the keyboard (input method activated).
    property bool active: false
    // Last caret rectangle [x, y, w, h], surface-local.
    property var rect: null
    property bool unavailable: false

    // {output, x, y, width, height}: the caret in output-local logical px,
    // null = no usable caret (no field, or its window is unknown).
    // The focused window's rect (output-local), null = unknown.
    readonly property var focusedWin: {
        const dep = root.compositor?.windowState;
        const output = root.compositor?.focusedOutput ?? "";
        const win = (root.compositor?.windowRects(output) ?? []).find(w => w.focused);
        return win ? Object.assign({ output: output }, win) : null;
    }
    readonly property var anchor: {
        const r = root.rect;
        const win = root.focusedWin;
        if (!root.active || !r || !win || (root.registry?.takesKeyboard ?? false))
            return null;
        const output = win.output;
        const off = calibration.offsetFor(win);
        const z = win.zoom ?? 1;
        return {
            output: output,
            x: win.x + (r[0] - off[0]) * z,
            y: win.y + (r[1] - off[1]) * z,
            width: Math.max(1, r[2] * z),
            height: Math.max(1, r[3] * z)
        };
    }

    property alias calibration: calibration
    CaretCalibration {
        id: calibration
        compositor: root.compositor
        currentRect: root.active ? root.rect : null
    }
    // Measure the margin of a window the first time a field there has the
    // caret (and again after it moved, until a run succeeds).
    readonly property var calibrationKey: root.active && root.focusedWin && root.rect && !(root.registry?.takesKeyboard ?? false)
        ? `${root.focusedWin.id}|${root.rect.join(",")}` : ""
    onCalibrationKeyChanged: if (root.calibrationKey !== "") calibration.note(root.focusedWin, root.rect, false)
    onActiveChanged: if (root.active && root.focusedWin && root.rect) calibration.note(root.focusedWin, root.rect, true)

    // The retry below writes `running` (a restart), which breaks the binding.
    onWantedChanged: helper.running = root.wanted && !root.unavailable

    Process {
        id: helper
        running: root.wanted && !root.unavailable
        command: ["python3", "-I", `${Quickshell.shellDir}/scripts/keyboard/caret.py`]
        stdout: SplitParser {
            onRead: line => {
                let msg = null;
                try {
                    msg = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (msg.rect)
                    root.rect = msg.rect;
                if (msg.active !== undefined)
                    root.active = msg.active === true;
            }
        }
        stderr: SplitParser {
            onRead: line => console.log("[caret]", line)
        }
        onExited: code => {
            root.active = false;
            if (code === 3)
                root.unavailable = true;
            if (root.wanted)
                retry.restart();
        }
    }
    // Restart after a crash; with another input method running, look
    // again rarely (it may be quit).
    Timer {
        id: retry
        interval: root.unavailable ? (root.cfg.caretRetryBusyMs ?? 60000) : (root.cfg.caretRetryMs ?? 3000)
        onTriggered: {
            root.unavailable = false;
            helper.running = root.wanted;
        }
    }
}
