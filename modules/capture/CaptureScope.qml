import QtQuick
import Quickshell
import Quickshell.Io
import "../../config"

// Capture orchestrator (shell-level, spans ALL monitors — the one module
// that is not confined to the focused screen). Flow (spec + pShell tools):
//   1. Island.openCapture() → begin(): every output is grabbed (grim PPM,
//      ~60ms) BEFORE anything moves, so the frozen frame is the clean bar.
//   2. Overlays map (frozen backdrop with a live hole over the island band,
//      dim, crosshair) and the island starts its part: content blur->fades
//      out, the background is handed over via steal(rect) and becomes the
//      square that arcs to the cursor and chases it with the mode icon,
//      while the island replays appearFromEdge (the "second instance").
//   3. Modes (Tab / wheel / 1-5 / icon in the square): shot = flameshot-
//      style region editor, record = selection → audio chips → recording,
//      ai = selection → inline OCR (+ Lens), scan = selection → QR /
//      barcodes (zbarimg), color = pipette, window = pick
//      a window as the selection. One screen claims the session once a
//      selection / colour panel exists (editScreen).
//   4. done()/cancel()/startRecording(): fade out → unmap → (recording only
//      starts after the overlay is gone).
Scope {
    id: root
    required property var recorder
    required property var theme
    required property var compositor
    property var events: null

    readonly property var cfg: Config.data.capture
    readonly property alias actions: actionsService
    readonly property alias motion: motionState

    property bool grabbing: false
    property bool grabbed: false
    property bool active: false
    property bool closing: false
    // Closing into a region recording: the WHOLE overlay (frozen backdrop
    // included) fades, so the live RecordRegionOverlay below crossfades in —
    // its frame takes over the selection frame (a backdrop that stayed opaque
    // and then unmapped made the dim + frame blink).
    property bool handover: false
    // The island background has been handed over (square on screen).
    property bool stolen: false
    property string mode: "shot"
    property string sessionStamp: ""
    property var island: null
    // Global live band over the island (see CaptureBackdrop).
    property var hole: null
    property string editScreen: ""
    property bool hasSelection: false
    property var preset: null
    property bool cursorKnown: false
    property bool windowsAvailable: false
    property var pendingAction: null
    property var queued: null

    readonly property var modes: (root.cfg.modes ?? ["shot"]).filter(m =>
        (m !== "record" || !root.recorder.recording) && (m !== "window" || root.windowsAvailable))
    readonly property string cursorScreen: root.screenAt(motionState.cursorX, motionState.cursorY)?.name ?? ""
    readonly property string activeScreen: root.editScreen !== "" ? root.editScreen : root.cursorScreen

    function glyph(m: string): string {
        return { shot: "", record: "", scan: "", ai: "", color: "", window: "" }[m] ?? "";
    }

    function glyphColor(m: string): color {
        return m === "record" ? root.theme.accentRed : root.theme.islandFg;
    }

    function screenAt(gx: real, gy: real): var {
        return Quickshell.screens.find(s => gx >= s.x && gx < s.x + s.width && gy >= s.y && gy < s.y + s.height) ?? null;
    }

    function srcFor(name: string): string {
        return actionsService.srcPath(name, root.sessionStamp);
    }

    // The hole in a screen's local coordinates (zero rect = none).
    function holeOn(name: string): rect {
        const s = Quickshell.screens.find(x => x.name === name);
        const h = root.hole;
        if (!s || !h || h.screen !== name)
            return Qt.rect(0, 0, 0, 0);
        return Qt.rect(h.x - s.x, 0, h.width, h.y - s.y + h.height);
    }

    // screen/island: where the island lives; mode "" = config default.
    // While a session runs a second call switches/cycles the mode.
    function begin(screen: var, island: var, mode: string): void {
        // Hotkey during the fade-out: a NEW session once this one is gone.
        if (root.closing) {
            root.queued = { screen: screen, island: island, mode: mode };
            return;
        }
        if (root.grabbing || root.active) {
            if (mode !== "" && root.modes.includes(mode))
                root.switchMode(mode);
            else if (!root.hasSelection)
                root.cycle(1);
            return;
        }
        closeTimer.stop();
        actionTimer.stop();
        root.windowsAvailable = Quickshell.screens.some(s => root.compositor.windowRects(s.name).length > 0);
        const wanted = mode !== "" ? mode : root.cfg.defaultMode;
        root.mode = root.modes.includes(wanted) ? wanted : root.modes[0];
        root.island = island;
        root.hole = island ? island.captureHole() : null;
        root.stolen = false;
        root.closing = false;
        root.grabbed = false;
        root.editScreen = "";
        root.hasSelection = false;
        root.preset = null;
        root.cursorKnown = false;
        motionState.reset();
        // Until the pointer reports in, aim at the island screen's centre.
        const s = screen ?? Quickshell.screens[0];
        motionState.cursorX = (s?.x ?? 0) + (s?.width ?? 0) / 2;
        motionState.cursorY = (s?.y ?? 0) + (s?.height ?? 0) / 2;
        root.sessionStamp = Date.now().toString();
        root.grabbing = true;
        grabProc.command = actionsService.grabCommand(Quickshell.screens.map(x => x.name), root.sessionStamp);
        grabProc.running = true;
    }

    // Grab done: map the overlays and let the island start its part.
    function onGrabbed(): void {
        root.grabbing = false;
        root.grabbed = true;
        root.active = true;
        motionState.dimLevel = 1;
        root.island?.startCaptureSteal();
        // niri sends no pointer enter to a fresh layer until the mouse moves:
        // a ±1px virtual-pointer nudge delivers it (driftwm does it on map).
        if (Quickshell.env("NIRI_SOCKET"))
            Quickshell.execDetached(actionsService.uvScript("nudge.py", []));
    }

    // Island hands its background over; false = no longer wanted (the
    // island then just closes its module instead of hiding).
    function steal(rect: var): bool {
        if (!root.active || root.closing)
            return false;
        root.stolen = true;
        motionState.launch(rect);
        if (root.hasSelection)
            squareHide.restart();
        return true;
    }

    function cycle(step: int): void {
        const i = root.modes.indexOf(root.mode);
        root.switchMode(root.modes[(i + step + root.modes.length) % root.modes.length]);
    }

    function setMode(index: int): void {
        if (index >= 0 && index < root.modes.length)
            root.switchMode(root.modes[index]);
    }

    // shot / record / ai share one RegionEditor (same Loader component):
    // switching among them keeps the selection — the editor re-applies the
    // mode's follow-up itself. Any other switch rebuilds the tool.
    readonly property var editorModes: ["shot", "record", "ai", "scan"]

    function switchMode(m: string): void {
        if (m === root.mode)
            return;
        const keep = root.editorModes.includes(root.mode) && root.editorModes.includes(m);
        root.mode = m;
        if (keep)
            return;
        root.editScreen = "";
        root.selectionChanged(false);
    }

    function pointerAt(gx: real, gy: real): void {
        motionState.cursorX = gx;
        motionState.cursorY = gy;
        const b = motionState.bounds;
        if (!(gx >= b.x && gx < b.x + b.width && gy >= b.y && gy < b.y + b.height)) {
            const s = Quickshell.screens.find(s => gx >= s.x && gx < s.x + s.width && gy >= s.y && gy < s.y + s.height);
            if (s)
                motionState.bounds = Qt.rect(s.x, s.y, s.width, s.height);
        }
        if (!root.cursorKnown) {
            root.cursorKnown = true;
            motionState.crossLevel = root.hasSelection ? 0 : 1;
        }
    }

    // A screen takes over the session ("" = released).
    function claim(name: string): void {
        root.editScreen = name;
    }

    // Aim visuals (crosshair + square) hide while a selection exists. The
    // square lingers squareHideDelayMs: the toolbar / audio chips are born
    // from under it (EditorToolbar / AudioChooser) and fly out first.
    function selectionChanged(has: bool): void {
        root.hasSelection = has;
        motionState.crossLevel = has || !root.cursorKnown ? 0 : 1;
        squareHide.stop();
        if (!root.stolen)
            return;
        if (has)
            squareHide.restart();
        else
            motionState.squareLevel = 1;
    }

    Timer {
        id: squareHide
        interval: root.cfg.squareHideDelayMs
        onTriggered: if (root.hasSelection) motionState.squareLevel = 0
    }

    // Window mode click: the editor on that screen starts with this rect.
    function pickWindow(name: string, r: rect): void {
        root.preset = { screen: name, rect: r };
        root.mode = "shot";
        root.editScreen = name;
    }

    function takePreset(name: string): var {
        const p = root.preset;
        if (!p || p.screen !== name)
            return null;
        root.preset = null;
        return p.rect;
    }

    function cancel(): void {
        root.finish(null);
    }

    // The tool already ran its action (clipboard / file / OCR copy).
    function done(): void {
        root.finish(null);
    }

    // Global logical rect + the same box in the output's physical px;
    // recording starts once the overlay is gone.
    function startRecording(r: rect, audio: string, output: string, phys: var): void {
        const geo = `${Math.round(r.x)},${Math.round(r.y)} ${Math.max(1, Math.round(r.width))}x${Math.max(1, Math.round(r.height))}`;
        root.recorder.prepareRegion(output, phys);
        root.handover = root.recorder.regionPending;
        root.finish(() => root.recorder.start(geo, audio, output, phys));
    }

    function finish(action: var): void {
        if (root.grabbing) {
            root.grabbing = false;
            grabProc.running = false;
            root.island?.abortCapture();
            return;
        }
        if (!root.active || root.closing)
            return;
        root.pendingAction = action;
        root.closing = true;
        motionState.dimLevel = 0;
        motionState.crossLevel = 0;
        motionState.squareLevel = 0;
        closeTimer.restart();
    }

    // IPC "captureScreen": the active screen's main action.
    function confirm(): void {
        for (const o of overlays.instances) {
            if (o.item?.name === root.activeScreen)
                o.item.tool?.confirm();
        }
    }

    // Headless introspection (Island.debugState).
    function debugInfo(): var {
        return {
            grabbing: root.grabbing,
            active: root.active,
            closing: root.closing,
            stolen: root.stolen,
            mode: root.mode,
            modes: root.modes,
            editScreen: root.editScreen,
            activeScreen: root.activeScreen,
            hasSelection: root.hasSelection,
            cursorKnown: root.cursorKnown,
            smartRects: overlays.instances.map(o => o.item?.tool?.smartRects?.length ?? -1),
            toolSelection: overlays.instances.map(o => o.item?.tool?.hasSelection ?? null),
            square: [motionState.centerX, motionState.centerY, motionState.w, motionState.h, motionState.flight, motionState.chasing]
        };
    }

    CaptureMotion {
        id: motionState
        cfg: root.cfg
    }

    CaptureActions {
        id: actionsService
        cfg: root.cfg
        events: root.events
    }
    // Google Lens upload running (StatusFeeds `lens`).
    readonly property bool lensBusy: actionsService.lensBusy

    Process {
        id: grabProc
        onExited: code => {
            if (!root.grabbing)
                return;
            if (code === 0) {
                root.onGrabbed();
            } else {
                root.grabbing = false;
                root.island?.abortCapture();
            }
        }
    }

    // Fade out -> unmap -> (compositor drops the overlay) -> act.
    Timer {
        id: closeTimer
        interval: root.cfg.fadeOutMs
        onTriggered: {
            root.active = false;
            root.closing = false;
            root.handover = false;
            root.stolen = false;
            root.editScreen = "";
            root.hasSelection = false;
            motionState.reset();
            if (root.pendingAction)
                actionTimer.restart();
            const q = root.queued;
            root.queued = null;
            if (q)
                Qt.callLater(() => q.island ? q.island.openCapture(q.mode) : root.begin(q.screen, null, q.mode));
        }
    }

    Timer {
        id: actionTimer
        interval: root.cfg.shotDelayMs
        onTriggered: {
            const a = root.pendingAction;
            root.pendingAction = null;
            if (a)
                a();
        }
    }

    Variants {
        id: overlays
        model: Quickshell.screens

        delegate: Loader {
            id: overlayLoader
            required property ShellScreen modelData
            active: root.active

            sourceComponent: CaptureOverlay {
                targetScreen: overlayLoader.modelData
                capture: root
                motion: motionState
                theme: root.theme
            }
        }
    }
}
