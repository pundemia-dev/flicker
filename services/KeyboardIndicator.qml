import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Keyboard pill policy (macOS input-source / Caps Lock indicator, after
// solium's lua/keyboard_indicator.lua): `what` = "caps" while Caps Lock is
// on, "layout" for `layoutShowMs` after a layout switch (then back to
// "caps" if it is still on, else ""), "" = hidden. `label` = the short name
// of the current layout (EN, RU). Drawn by modules/keyboard/KeyboardOverlay
// (one per screen) UNDER THE TEXT CARET (services/Caret), or — no focused
// text field — under the mouse pointer: nothing reports the pointer, so a
// show `probe()`s it (every overlay maps a full-screen input surface for a
// moment; the compositor sends wl_pointer.enter with the position ~17 ms
// later, verified on driftwm), `pointerSeen` ends it. Caps Lock at the
// caret is held while it is on (macOS); at the pointer only `capsPointerMs`.
//
// Layout comes from services/KeyboardLayout (drift subscribe / niri
// event-stream). Caps Lock has no compositor IPC (neither drift nor niri
// report locked modifiers), so it is read from the keyboard LED in sysfs
// (`/sys/class/leds/*::capslock`): the compositor sets the LEDs of EVERY
// keyboard on a lock change (verified on driftwm with a uinput keyboard).
// The kernel changes that file without a VFS write, so inotify never fires —
// it is polled every `capsPollMs` (a 1-byte sysfs read).
// NOTE: with `grp:caps_toggle` the Caps key switches the layout; Caps Lock
// itself is Shift+Caps.
Scope {
    id: root
    required property var keyboardLayout
    required property var caret

    readonly property var cfg: Config.data.keyboard ?? ({})
    readonly property bool enabled: root.cfg.enabled ?? true

    property bool caps: false
    property string what: ""
    // Bumped on every layout flash (same label again replays the pop).
    property int serial: 0
    // A layout flash is on show. Own flag: inside a one-shot Timer's
    // onTriggered `running` is still true.
    property bool flashing: false

    readonly property string label: {
        const code = (root.keyboardLayout?.code ?? "").toLowerCase();
        const name = root.keyboardLayout?.layout ?? "";
        const labels = root.cfg.labels ?? ({});
        const mapped = labels[code] ?? labels[name] ?? "";
        if (mapped !== "")
            return mapped;
        return (code !== "" ? code : name).slice(0, 2).toUpperCase();
    }

    property bool quiet: true
    Timer {
        running: true
        interval: root.cfg.startupQuietMs ?? 1500
        onTriggered: root.quiet = false
    }

    // Where the pill goes: the caret, else the pointer.
    readonly property bool atCaret: root.caret?.anchor !== null && root.caret?.anchor !== undefined
    // {output, x, y} of the pointer at the last probe (output-local).
    property var pointer: null
    property bool probing: false
    property int probeSerial: 0
    function probe(): void {
        if (root.atCaret)
            return;
        root.probeSerial++;
        root.probing = true;
        probeEnd.restart();
    }
    function pointerSeen(output: string, x: real, y: real): void {
        if (!root.probing)
            return;
        root.pointer = { output: output, x: x, y: y };
        root.probing = false;
        probeEnd.stop();
    }
    // Pointer on no output we cover (or no enter at all): give up, the
    // overlay keeps the last known pointer / the screen centre.
    Timer {
        id: probeEnd
        interval: root.cfg.probeTimeoutMs ?? 250
        onTriggered: root.probing = false
    }
    // Caps Lock pill at the pointer is on show (own flag, see `flashing`).
    property bool capsPointerOn: false
    Timer {
        id: capsPointer
        interval: root.cfg.capsPointerMs ?? 2500
        onTriggered: {
            root.capsPointerOn = false;
            root.refresh();
        }
    }
    Connections {
        target: root.caret
        function onAnchorChanged(): void { root.refresh(); }
    }

    function refresh(): void {
        const capsShown = root.caps && (root.cfg.caps ?? true) && (root.atCaret || root.capsPointerOn);
        if (!root.enabled)
            root.what = "";
        else if (root.flashing)
            root.what = "layout";
        else
            root.what = capsShown ? "caps" : "";
    }

    Connections {
        target: root.keyboardLayout
        function onLayoutChanged(): void { root.layoutSwitched(); }
        function onCodeChanged(): void { root.layoutSwitched(); }
    }
    function layoutSwitched(): void {
        if (root.quiet || !(root.cfg.layout ?? true) || root.label === "")
            return;
        root.startFlash();
    }
    function startFlash(): void {
        root.probe();
        root.serial++;
        root.flashing = true;
        flash.restart();
        root.refresh();
    }
    // Debug / preview (IPC `island keyboardDemo`).
    function demo(kind: string): void {
        if (kind === "caps") {
            root.caps = !root.caps;
        } else {
            root.startFlash();
        }
    }

    onCapsChanged: {
        if (root.caps && !root.atCaret) {
            root.probe();
            root.capsPointerOn = true;
            capsPointer.restart();
        }
        root.refresh();
    }
    onEnabledChanged: root.refresh()
    onCfgChanged: root.refresh()

    Timer {
        id: flash
        interval: root.cfg.layoutShowMs ?? 1200
        onTriggered: {
            root.flashing = false;
            root.refresh();
        }
    }

    // ---- Caps Lock LED ----
    property string ledPath: ""
    // No LED yet (or it went away): look again, also for a keyboard
    // plugged in later.
    Timer {
        interval: root.cfg.ledRescanMs ?? 10000
        repeat: true
        triggeredOnStart: true
        running: root.enabled && (root.cfg.caps ?? true) && root.ledPath === ""
        onTriggered: findLed.running = true
    }
    Process {
        id: findLed
        command: ["sh", "-c", "for f in /sys/class/leds/*::capslock/brightness; do [ -r \"$f\" ] && echo \"$f\" && break; done"]
        stdout: StdioCollector {
            onStreamFinished: root.ledPath = (text ?? "").trim()
        }
    }
    FileView {
        id: led
        path: root.ledPath
        blockLoading: true
        printErrors: false
        onLoaded: root.caps = parseInt(text().trim()) > 0
        // The keyboard went away (hidraw/input renumbered): find it again.
        onLoadFailed: {
            root.ledPath = "";
            root.caps = false;
        }
    }
    Timer {
        interval: root.cfg.capsPollMs ?? 150
        repeat: true
        running: root.enabled && (root.cfg.caps ?? true) && root.ledPath !== ""
        onTriggered: led.reload()
    }
}
