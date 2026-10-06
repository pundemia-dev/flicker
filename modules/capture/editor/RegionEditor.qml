import QtQuick
import Quickshell
import Quickshell.Io
import "../../../config"

// Flameshot-style region editor on one screen (port of pShell
// RegionEditor). Drag selects (click = whole screen), then the toolbar ring
// appears around the selection, which stays movable/resizable:
//   no tool → drag inside moves, edges/corners resize, drag outside
//             reselects, click on an object selects it (drag moves, Del);
//   tool    → drag draws; wheel = thickness; RMB = palette ring.
// Capture mode shapes the follow-up: shot = toolbar, record = audio chooser
// (recording starts on a chip), ai = OCR panel opens on the selection.
// Commit renders the selection + annotations through an offscreen composite
// at physical resolution (1:1 grab pixels, nothing resampled).
Item {
    id: root
    required property var capture
    required property var actions
    required property var theme
    required property var cfg
    required property string screenName
    required property real ox
    required property real oy
    required property real dpr
    required property string srcPath
    required property Item keyTarget

    readonly property string srcUrl: "file://" + root.srcPath
    readonly property int physW: Math.round(width * dpr)
    readonly property int physH: Math.round(height * dpr)

    // ── Tool contract (CaptureOverlay) ──────────────────────────────
    readonly property var cutRect: selVisible ? Qt.rect(selX, selY, selW, selH) : null
    readonly property bool dimmed: true

    property real cursorX: 0
    property real cursorY: 0
    property bool hasSelection: false
    property real selX: 0
    property real selY: 0
    property real selW: 0
    property real selH: 0
    property string dragMode: ""   // select | move | resize | draw | moveObj
    readonly property bool selVisible: hasSelection || dragMode === "select"
    readonly property bool interacting: dragMode !== ""
    property string activeTool: ""
    property bool paletteOpen: false
    property point palettePos: Qt.point(0, 0)
    property bool pendingRecord: false
    property bool committing: false
    property alias model: editorModel
    property alias ocrPanel: ocr

    onHasSelectionChanged: root.capture.selectionChanged(root.hasSelection)
    onActiveToolChanged: {
        editorModel.selectedObj = -1;
        editorModel.selObjRect = null;
    }

    function setCursor(x: real, y: real): void {
        root.cursorX = x;
        root.cursorY = y;
        root.capture.pointerAt(root.ox + x, root.oy + y);
    }

    function physRect(): var {
        return {
            x: Math.round(root.selX * root.dpr),
            y: Math.round(root.selY * root.dpr),
            width: Math.max(1, Math.round(root.selW * root.dpr)),
            height: Math.max(1, Math.round(root.selH * root.dpr))
        };
    }

    // Selection established (drag release, click, window/smart snap):
    // the capture mode decides the follow-up.
    function selectionReady(): void {
        if (!root.hasSelection)
            return;
        if (root.capture.mode === "record")
            root.pendingRecord = true;
        else if (root.capture.mode === "ai" && !ocr.open)
            ocr.toggle();
        else if (ocr.open)
            ocr.recrop();
    }

    // Mode switched among shot / record / ai with a live selection.
    Connections {
        target: root.capture
        function onModeChanged(): void {
            if (!root.hasSelection)
                return;
            root.pendingRecord = root.capture.mode === "record";
            if (root.capture.mode === "ai" && !ocr.open)
                ocr.toggle();
        }
    }

    function setSelection(r: var): void {
        root.selX = r.x;
        root.selY = r.y;
        root.selW = r.width;
        root.selH = r.height;
        root.hasSelection = r.width >= 2 && r.height >= 2;
        root.capture.claim(root.screenName);
        root.selectionReady();
    }

    function selectAll(): void {
        root.setSelection(Qt.rect(0, 0, root.width, root.height));
    }

    // ── Commit: composite → PNG → clipboard / file ──────────────────
    function commit(copy: bool, save: bool): void {
        if (!root.hasSelection || root.committing)
            return;
        if (editorModel.editingObj >= 0)
            root.commitEditingText();
        root.committing = true;
        const out = root.actions.scratchPng("out", root.screenName);
        const ok = composite.grabToImage(res => {
            res.saveToFile(out);
            root.actions.deliver(out, copy, save);
            root.capture.done();
        });
        if (!ok)
            root.committing = false;
    }

    function commitDefault(): void {
        root.commit(root.cfg.copyToClipboard, root.actions.saveDir !== "");
    }

    function lens(): void {
        if (!root.hasSelection)
            return;
        root.actions.lens(root.srcPath, root.physRect(), root.screenName);
        root.capture.done();
    }

    function startRecording(audio: string): void {
        if (!root.hasSelection)
            return;
        root.capture.startRecording(Qt.rect(root.ox + root.selX, root.oy + root.selY, root.selW, root.selH), audio);
    }

    function commitEditingText(): void {
        annotations.commitEditingText();
    }

    // Wheel feedback: "<n> px" bubble next to the cursor for a moment.
    property bool thicknessHintShown: false
    function thicknessHint(): void {
        root.thicknessHintShown = true;
        hintTimer.restart();
    }

    Timer {
        id: hintTimer
        interval: root.cfg.thicknessHintMs
        onTriggered: root.thicknessHintShown = false
    }

    function openPalette(): void {
        root.palettePos = Qt.point(root.cursorX, root.cursorY);
        root.paletteOpen = true;
    }

    // ── Keys (overlay routes them here first) ───────────────────────
    function handleEscape(): bool {
        if (editorModel.editingObj >= 0) {
            root.commitEditingText();
            return true;
        }
        if (root.paletteOpen) {
            root.paletteOpen = false;
            return true;
        }
        if (ocr.open) {
            ocr.open = false;
            return true;
        }
        if (root.pendingRecord && root.capture.mode !== "record") {
            root.pendingRecord = false;
            return true;
        }
        if (root.activeTool !== "") {
            root.activeTool = "";
            return true;
        }
        if (editorModel.selectedObj >= 0) {
            editorModel.selectedObj = -1;
            editorModel.selObjRect = null;
            return true;
        }
        return false;
    }

    // Enter/Space: the current context's main action.
    function confirm(): void {
        if (editorModel.editingObj >= 0)
            return;
        // No selection yet: the whole screen becomes the selection and the
        // mode's follow-up (audio chips / OCR) opens; only a shot commits.
        if (!root.hasSelection) {
            root.selectAll();
            if (root.capture.mode === "shot")
                root.commitDefault();
            return;
        }
        if (root.pendingRecord)
            root.startRecording("");
        else if (ocr.open) {
            if (ocr.running)
                return; // Enter would close before the text arrives
            if (ocr.text !== "")
                root.actions.copyText(ocr.text, I18n.tr("Text copied"));
            root.capture.done();
        } else if (root.capture.mode !== "ai")
            root.commitDefault();
    }

    function handleKey(event: var): bool {
        if (editorModel.editingObj >= 0)
            return false;
        const ctrl = event.modifiers & Qt.ControlModifier;
        if (ctrl && event.key === Qt.Key_C)
            root.commit(true, false);
        else if (ctrl && event.key === Qt.Key_S)
            root.commit(false, true);
        else if (ctrl && event.key === Qt.Key_Z && (event.modifiers & Qt.ShiftModifier))
            editorModel.redo();
        else if (ctrl && event.key === Qt.Key_Z)
            editorModel.undo();
        else if (ctrl && event.key === Qt.Key_Y)
            editorModel.redo();
        else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace)
            editorModel.deleteSelected();
        else
            return false;
        return true;
    }

    EditorModel {
        id: editorModel
        cfg: root.cfg
    }

    // Hidden full grab: the blur/pixelate tools sample it (a ShaderEffect
    // source may be invisible; the backdrop itself is cut around the island).
    Image {
        id: effectBase
        anchors.fill: parent
        visible: false
        source: root.srcUrl
        asynchronous: true
    }

    // ── Smart regions (optional): double-click snaps to a content box ──
    property var smartRects: []
    readonly property var smartHover: root.cfg.smartRegions && !root.hasSelection
        ? root.smartRectAt(root.cursorX, root.cursorY) : null

    function smartRectAt(x: real, y: real): var {
        let best = null;
        for (const r of root.smartRects) {
            if (x >= r.x && x <= r.x + r.width && y >= r.y && y <= r.y + r.height && (!best || r.width * r.height < best.width * best.height))
                best = r;
        }
        return best;
    }

    // Detected once per grab: editors are rebuilt on mode / screen
    // switches, the detector (~1.6s CPU) must not rerun each time.
    Component.onCompleted: {
        const cached = root.actions.smartCache[root.srcPath];
        if (cached)
            root.smartRects = cached;
    }

    Process {
        running: root.cfg.smartRegions && !root.actions.smartCache[root.srcPath]
        command: root.actions.uvScript("regions.py", [root.srcPath])
        stdout: StdioCollector {
            id: regionsOut
            onStreamFinished: {
                try {
                    root.smartRects = JSON.parse(regionsOut.text).map(r => Qt.rect(r.x / root.dpr, r.y / root.dpr, r.width / root.dpr, r.height / root.dpr));
                } catch (e) {
                    root.smartRects = [];
                }
                root.actions.cacheSmart(root.srcPath, root.smartRects);
            }
        }
    }

    // ── Layers ──────────────────────────────────────────────────────
    EditorAnnotations {
        id: annotations
        anchors.fill: parent
        editor: root
        effectSource: effectBase
    }

    SelectionFrame {
        anchors.fill: parent
        editor: root
    }

    EditorInput {
        anchors.fill: parent
        editor: root
    }

    EditorToolbar {
        id: toolbar
        anchors.fill: parent
        editor: root
        visible: root.hasSelection && root.dragMode === "" && !root.committing && !root.pendingRecord
    }

    AudioChooser {
        anchors.fill: parent
        editor: root
        visible: root.hasSelection && root.pendingRecord && root.dragMode === ""
    }

    OcrPanel {
        id: ocr
        anchors.fill: parent
        editor: root
        clearance: root.cfg.toolButtonSize + root.cfg.toolSpacing * 2
    }

    PaletteRing {
        anchors.fill: parent
        editor: root
    }

    EditorComposite {
        id: composite
        editor: root
        effectSource: effectBase
    }
}
