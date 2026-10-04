import QtQuick

// Pointer interaction of the region editor (port of pShell RegionEditor's
// MouseArea + interaction steps): select / move / resize the frame, draw
// with the active tool, select + drag objects, wheel = thickness, RMB =
// palette, double-click = smart-region snap.
MouseArea {
    id: root
    required property var editor

    readonly property var ed: root.editor
    readonly property var m: root.editor.model
    property real pressX: 0
    property real pressY: 0
    property rect orig: Qt.rect(0, 0, 0, 0)
    property int edges: 0          // bits: 1=left 2=right 4=top 8=bottom
    property var origRow: null
    property var penPts: []
    property var pressSmart: null

    enabled: !root.ed.committing
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true

    function clampv(v: real, lo: real, hi: real): real {
        return Math.max(lo, Math.min(hi, v));
    }

    function edgeAt(x: real, y: real): int {
        if (!root.ed.hasSelection)
            return 0;
        const t = root.ed.cfg.edgeGrab, e = root.ed;
        const inX = x >= e.selX - t && x <= e.selX + e.selW + t;
        const inY = y >= e.selY - t && y <= e.selY + e.selH + t;
        let r = 0;
        if (Math.abs(x - e.selX) <= t && inY) r |= 1;
        if (Math.abs(x - (e.selX + e.selW)) <= t && inY) r |= 2;
        if (Math.abs(y - e.selY) <= t && inX) r |= 4;
        if (Math.abs(y - (e.selY + e.selH)) <= t && inX) r |= 8;
        return r;
    }

    function insideSel(x: real, y: real): bool {
        const e = root.ed;
        return e.hasSelection && x >= e.selX && x <= e.selX + e.selW && y >= e.selY && y <= e.selY + e.selH;
    }

    function updateSelect(mx: real, my: real): void {
        const x = clampv(mx, 0, width), y = clampv(my, 0, height);
        root.ed.selX = Math.min(root.pressX, x);
        root.ed.selY = Math.min(root.pressY, y);
        root.ed.selW = Math.abs(x - root.pressX);
        root.ed.selH = Math.abs(y - root.pressY);
    }

    function applyResize(mx: real, my: real): void {
        const o = root.orig, dx = mx - root.pressX, dy = my - root.pressY;
        let x1 = o.x, y1 = o.y, x2 = o.x + o.width, y2 = o.y + o.height;
        if (root.edges & 1) x1 = clampv(o.x + dx, 0, x2 - 1);
        if (root.edges & 2) x2 = clampv(o.x + o.width + dx, x1 + 1, width);
        if (root.edges & 4) y1 = clampv(o.y + dy, 0, y2 - 1);
        if (root.edges & 8) y2 = clampv(o.y + o.height + dy, y1 + 1, height);
        root.ed.selX = x1;
        root.ed.selY = y1;
        root.ed.selW = x2 - x1;
        root.ed.selH = y2 - y1;
    }

    function startDraw(mx: real, my: real): void {
        const tool = root.ed.activeTool;
        root.m.preState = root.m.serialize();
        const row = root.m.newRow(tool);
        if (tool === "counter") {
            row.rx = mx;
            row.ry = my;
            row.n = root.m.counterNext++;
            root.m.objects.append(row);
            root.m.pushUndo(root.m.preState);
            root.m.preState = null;
            return;
        }
        if (tool === "text") {
            row.rx = mx;
            row.ry = my - row.fontPx;
            row.editing = true;
            root.m.objects.append(row);
            root.m.editingObj = root.m.objects.count - 1;
            return;
        }
        row.rx = row.px2 = mx;
        row.ry = row.py2 = my;
        if (tool === "pencil") {
            root.penPts = [{ x: mx, y: my }];
            row.ptsJson = JSON.stringify(root.penPts);
        }
        root.m.objects.append(row);
        root.ed.dragMode = "draw";
    }

    function applyDraw(mx: real, my: real): void {
        const i = root.m.objects.count - 1, tool = root.ed.activeTool, o = root.m.objects;
        if (tool === "pencil") {
            root.penPts.push({ x: mx, y: my });
            o.setProperty(i, "ptsJson", JSON.stringify(root.penPts));
        } else if (tool === "line" || tool === "arrow" || tool === "marker") {
            o.setProperty(i, "px2", mx);
            o.setProperty(i, "py2", my);
        } else {
            o.setProperty(i, "rx", Math.min(root.pressX, mx));
            o.setProperty(i, "ry", Math.min(root.pressY, my));
            o.setProperty(i, "rw", Math.abs(mx - root.pressX));
            o.setProperty(i, "rh", Math.abs(my - root.pressY));
        }
    }

    function finishDraw(): void {
        const i = root.m.objects.count - 1, r = root.m.objects.get(i);
        let valid = true;
        if (r.type === "rect" || r.type === "ellipse" || r.type === "blur" || r.type === "pixelate")
            valid = r.rw > 2 && r.rh > 2;
        else if (r.type === "line" || r.type === "arrow" || r.type === "marker")
            valid = Math.hypot(r.px2 - r.rx, r.py2 - r.ry) > 2;
        else if (r.type === "pencil")
            valid = JSON.parse(r.ptsJson).length > 1;
        if (valid)
            root.m.pushUndo(root.m.preState);
        else
            root.m.objects.remove(i);
        root.m.preState = null;
    }

    function startMoveObj(i: int): void {
        root.ed.dragMode = "moveObj";
        root.m.preState = root.m.serialize();
        const r = root.m.objects.get(i);
        root.origRow = { rx: r.rx, ry: r.ry, px2: r.px2, py2: r.py2, pts: JSON.parse(r.ptsJson) };
    }

    function applyMoveObj(mx: real, my: real): void {
        const dx = mx - root.pressX, dy = my - root.pressY, i = root.m.selectedObj, o = root.m.objects, g = root.origRow;
        o.setProperty(i, "rx", g.rx + dx);
        o.setProperty(i, "ry", g.ry + dy);
        o.setProperty(i, "px2", g.px2 + dx);
        o.setProperty(i, "py2", g.py2 + dy);
        if (o.get(i).type === "pencil")
            o.setProperty(i, "ptsJson", JSON.stringify(g.pts.map(p => ({ x: p.x + dx, y: p.y + dy }))));
        root.m.selObjRect = root.m.bounds(i);
    }

    cursorShape: {
        const e = root.ed;
        if (!e.hasSelection || e.activeTool !== "")
            return Qt.CrossCursor;
        const g = root.edgeAt(e.cursorX, e.cursorY);
        if (g === 5 || g === 10) return Qt.SizeFDiagCursor;
        if (g === 6 || g === 9) return Qt.SizeBDiagCursor;
        if (g === 1 || g === 2) return Qt.SizeHorCursor;
        if (g === 4 || g === 8) return Qt.SizeVerCursor;
        return root.insideSel(e.cursorX, e.cursorY) ? Qt.SizeAllCursor : Qt.CrossCursor;
    }

    onWheel: wheel => {
        if (!root.ed.hasSelection) {
            root.ed.capture.cycle(wheel.angleDelta.y > 0 ? -1 : 1);
            return;
        }
        root.m.setThickness(root.m.thickness + (wheel.angleDelta.y > 0 ? 1 : -1));
        root.ed.thicknessHint();
    }

    onPressed: mouse => {
        const e = root.ed;
        e.setCursor(mouse.x, mouse.y);
        if (mouse.button === Qt.RightButton) {
            if (!e.hasSelection)
                e.capture.cancel();
            else if (e.paletteOpen)
                e.paletteOpen = false;
            else
                e.openPalette();
            return;
        }
        if (e.paletteOpen) {
            e.paletteOpen = false;
            return;
        }
        if (root.m.editingObj >= 0) {
            e.commitEditingText();
            return;
        }
        e.capture.claim(e.screenName);
        root.pressX = mouse.x;
        root.pressY = mouse.y;
        if (!e.hasSelection) {
            // Candidate under the press (the frame hides once dragging).
            root.pressSmart = e.smartRectAt(mouse.x, mouse.y);
            e.dragMode = "select";
            root.updateSelect(mouse.x, mouse.y);
            return;
        }
        if (e.activeTool !== "") {
            root.startDraw(mouse.x, mouse.y);
            return;
        }
        const g = root.edgeAt(mouse.x, mouse.y);
        if (g !== 0) {
            e.dragMode = "resize";
            root.edges = g;
            root.orig = Qt.rect(e.selX, e.selY, e.selW, e.selH);
            return;
        }
        if (root.insideSel(mouse.x, mouse.y)) {
            const hit = root.m.hit(mouse.x, mouse.y);
            root.m.selectedObj = hit;
            root.m.selObjRect = hit >= 0 ? root.m.bounds(hit) : null;
            if (hit >= 0) {
                root.startMoveObj(hit);
            } else {
                e.dragMode = "move";
                root.orig = Qt.rect(e.selX, e.selY, e.selW, e.selH);
            }
            return;
        }
        root.m.selectedObj = -1;
        root.m.selObjRect = null;
        e.pendingRecord = false;
        root.pressSmart = e.smartRectAt(mouse.x, mouse.y);
        e.dragMode = "select";
        root.updateSelect(mouse.x, mouse.y);
    }

    onDoubleClicked: mouse => {
        const e = root.ed;
        if (mouse.button !== Qt.LeftButton || !e.cfg.smartRegions || e.activeTool !== "" || root.m.editingObj >= 0)
            return;
        const r = e.smartRectAt(mouse.x, mouse.y);
        if (r) {
            e.dragMode = "";
            e.setSelection(r);
        }
    }

    onPositionChanged: mouse => {
        const e = root.ed;
        e.setCursor(mouse.x, mouse.y);
        switch (e.dragMode) {
        case "select":
            root.updateSelect(mouse.x, mouse.y);
            break;
        case "draw":
            root.applyDraw(mouse.x, mouse.y);
            break;
        case "move":
            e.selX = clampv(root.orig.x + mouse.x - root.pressX, 0, width - e.selW);
            e.selY = clampv(root.orig.y + mouse.y - root.pressY, 0, height - e.selH);
            break;
        case "resize":
            root.applyResize(mouse.x, mouse.y);
            break;
        case "moveObj":
            root.applyMoveObj(mouse.x, mouse.y);
            break;
        }
    }

    onReleased: mouse => {
        const e = root.ed, mode = e.dragMode;
        if (mode === "select") {
            // Plain click = the highlighted smart region under the cursor
            // (what the blue candidate frame promises), else the whole
            // screen (flameshot). Taken at press: the frame hides while dragging.
            const click = Math.abs(mouse.x - root.pressX) < root.ed.cfg.minSelection && Math.abs(mouse.y - root.pressY) < root.ed.cfg.minSelection;
            const smart = click ? root.pressSmart : null;
            e.dragMode = "";
            e.setSelection(!click ? Qt.rect(e.selX, e.selY, e.selW, e.selH) : (smart ?? Qt.rect(0, 0, width, height)));
            return;
        }
        if (mode === "draw")
            root.finishDraw();
        else if (mode === "moveObj") {
            if (mouse.x !== root.pressX || mouse.y !== root.pressY)
                root.m.pushUndo(root.m.preState);
            root.m.preState = null;
        }
        e.dragMode = "";
        if (mode === "move" || mode === "resize")
            e.selectionReady();
    }
}
