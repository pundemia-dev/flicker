import QtQuick
import "../../../components"

// Flameshot-style button ring (port of pShell EditorToolbar): round buttons
// wrap around the selection — bottom edge (l→r), right (b→t), top (r→l),
// left (t→b). A side blocked by the screen edge is skipped; a full ring
// expands one cell outward and continues; when nothing fits outside
// (selection ≈ whole screen) buttons fall back to rows inside, bottom-up.
Item {
    id: root
    required property var editor

    readonly property var ed: root.editor
    readonly property var cfg: root.editor.cfg

    // Record is hidden while a recording runs (Recorder.start would refuse
    // and the overlay would just close).
    readonly property var buttons: root.allButtons.filter(b => b.kind !== "record" || !root.ed.capture.recorder.recording)
    readonly property var allButtons: [
        { kind: "tool", tool: "pencil", glyph: "" },
        { kind: "tool", tool: "line", glyph: "" },
        { kind: "tool", tool: "arrow", glyph: "" },
        { kind: "tool", tool: "rect", glyph: "" },
        { kind: "tool", tool: "ellipse", glyph: "" },
        { kind: "tool", tool: "marker", glyph: "" },
        { kind: "tool", tool: "text", glyph: "" },
        { kind: "tool", tool: "counter", glyph: "" },
        { kind: "tool", tool: "blur", glyph: "" },
        { kind: "tool", tool: "pixelate", glyph: "" },
        { kind: "swatch", glyph: "" },
        { kind: "undo", glyph: "" },
        { kind: "redo", glyph: "" },
        { kind: "copy", glyph: "" },
        { kind: "save", glyph: "" },
        { kind: "ocr", glyph: "" },
        { kind: "scan", glyph: "" },
        { kind: "lens", glyph: "" },
        { kind: "record", glyph: "" },
        { kind: "close", glyph: "" }
    ]

    // Birth (first appearance per selection): every button starts under the
    // chasing square (centre, local coords; the square is drawn above the
    // tools) and springs out to its ring slot while fading in. Later
    // re-appearances (after a frame move/resize) just glide between slots.
    property bool born: false
    property bool springy: false
    property bool bornOnce: false
    property point origin: Qt.point(0, 0)

    function birth(): void {
        const m = root.ed.capture.motion;
        root.origin = Qt.point(m.centerX - root.ed.ox - root.btn / 2, m.centerY - root.ed.oy - root.btn / 2);
        root.springy = false;
        root.born = false;
        root.springy = true;
        root.born = true;
        root.bornOnce = true;
    }

    onVisibleChanged: if (visible && !root.bornOnce) root.birth()

    // Stiffness gain of one axis: grows with the share of the OTHER axis'
    // distance, i.e. the shorter axis springs harder.
    function arcGain(other: real, own: real): real {
        const a = Math.abs(other), b = Math.abs(own);
        return 1 + root.cfg.birthArc * a / Math.max(1, a + b);
    }

    Connections {
        target: root.ed
        function onHasSelectionChanged(): void {
            if (!root.ed.hasSelection)
                root.bornOnce = false;
        }
    }

    readonly property real btn: root.cfg.toolButtonSize
    readonly property real sep: root.cfg.toolSpacing
    readonly property var positions: root.layout()

    // Resting rect of the OCR button: the OCR panel grows out of it.
    readonly property rect ocrButtonRect: {
        const p = root.positions[root.buttons.findIndex(b => b.kind === "ocr")];
        return p ? Qt.rect(p.x, p.y, root.btn, root.btn) : Qt.rect(0, 0, 0, 0);
    }

    function dispatch(b: var): void {
        const e = root.ed;
        switch (b.kind) {
        case "tool": e.activeTool = e.activeTool === b.tool ? "" : b.tool; break;
        case "swatch": e.openPalette(); break;
        case "undo": e.model.undo(); break;
        case "redo": e.model.redo(); break;
        case "copy": e.commit(true, false); break;
        case "save": e.commit(false, true); break;
        case "ocr": e.ocrPanel.toggle(); break;
        case "scan": e.scanPanel.toggle(); break;
        case "lens": e.lens(); break;
        case "record": e.pendingRecord = true; break;
        case "close": e.capture.cancel(); break;
        }
    }

    function layout(): var {
        const count = root.buttons.length, B = root.btn, S = root.sep, cell = B + S;
        const W = root.width, H = root.height, e = root.ed;
        let rx = e.selX, ry = e.selY, rw = e.selW, rh = e.selH;
        const pos = [];
        // Centred run of n cells along one side, preserving ring direction.
        const addRun = (horizontal, centre, fixed, n, forward) => {
            const cs = [];
            let c = centre - (n * cell - S) / 2;
            for (let k = 0; k < n; k++)
                cs.push(c + k * cell);
            if (!forward)
                cs.reverse();
            for (const v of cs) {
                if (pos.length >= count)
                    return;
                pos.push(horizontal ? { x: v, y: fixed } : { x: fixed, y: v });
            }
        };
        let guard = 0;
        while (pos.length < count && guard++ < 6) {
            const bB = ry + rh + S + B > H, bT = ry - S - B < 0, bR = rx + rw + S + B > W, bL = rx - S - B < 0;
            if (bB && bT && bR && bL)
                break;
            const perRow = Math.max(1, Math.floor((rw + S) / cell));
            const perCol = Math.max(1, Math.floor((rh + S) / cell));
            if (!bB && pos.length < count) addRun(true, rx + rw / 2, ry + rh + S, Math.min(perRow, count - pos.length), true);
            if (!bR && pos.length < count) addRun(false, ry + rh / 2, rx + rw + S, Math.min(perCol, count - pos.length), false);
            if (!bT && pos.length < count) addRun(true, rx + rw / 2, ry - S - B, Math.min(perRow, count - pos.length), false);
            if (!bL && pos.length < count) addRun(false, ry + rh / 2, rx - S - B, Math.min(perCol, count - pos.length), true);
            const nx = Math.max(0, rx - cell), ny = Math.max(0, ry - cell);
            const nx2 = Math.min(W, rx + rw + cell), ny2 = Math.min(H, ry + rh + cell);
            if (nx === rx && ny === ry && nx2 === rx + rw && ny2 === ry + rh)
                break;
            rx = nx;
            ry = ny;
            rw = nx2 - nx;
            rh = ny2 - ny;
        }
        if (pos.length < count) {
            const perRow = Math.max(1, Math.floor((e.selW + S) / cell));
            let y = e.selY + e.selH - S - B;
            while (pos.length < count) {
                addRun(true, e.selX + e.selW / 2, Math.max(0, y), Math.min(perRow, count - pos.length), true);
                y -= cell;
            }
        }
        for (const p of pos) {
            p.x = Math.max(0, Math.min(W - B, p.x));
            p.y = Math.max(0, Math.min(H - B, p.y));
        }
        return pos;
    }

    Repeater {
        model: root.buttons

        IconButton {
            required property var modelData
            required property int index
            theme: root.ed.theme
            readonly property point slot: root.positions[index] ?? Qt.point(0, 0)
            // Arc: the axis with the SHORTER way gets the stiffer spring, so it
            // finishes first and the long axis trails — a curved path out of
            // the bubble instead of a straight ray (birthArc 0 = straight).
            readonly property real arcX: root.cfg.birthSpring * root.arcGain(slot.y - root.origin.y, slot.x - root.origin.x)
            readonly property real arcY: root.cfg.birthSpring * root.arcGain(slot.x - root.origin.x, slot.y - root.origin.y)
            x: root.born ? slot.x : root.origin.x
            y: root.born ? slot.y : root.origin.y
            opacity: (root.born ? 1 : 0) * (disabled ? 0.4 : 1)
            Behavior on x { enabled: root.springy; Spring { stiffness: arcX; damp: root.cfg.birthDamping } }
            Behavior on y { enabled: root.springy; Spring { stiffness: arcY; damp: root.cfg.birthDamping } }
            Behavior on opacity { enabled: root.springy; NumberAnimation { duration: root.cfg.fadeInMs } }
            width: root.btn
            height: root.btn
            tile: true
            radius: root.cfg.toolRadius
            iconSize: root.cfg.toolIconSize
            glyph: modelData.glyph
            fg: modelData.kind === "swatch" ? root.ed.model.drawColor
                : (modelData.kind === "record" ? root.ed.theme.accentRed : root.ed.theme.islandFg)
            checked: (modelData.kind === "tool" && root.ed.activeTool === modelData.tool) || (modelData.kind === "ocr" && root.ed.ocrPanel.open)
                || (modelData.kind === "scan" && root.ed.scanPanel.open)
            disabled: modelData.kind === "undo" ? root.ed.model.undoStack.length === 0
                : (modelData.kind === "redo" ? root.ed.model.redoStack.length === 0 : false)
            onClicked: root.dispatch(modelData)
        }
    }
}
