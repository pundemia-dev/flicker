import QtQuick

// Annotation objects of the region editor (port of pShell RegionEditor's
// model half): one ListModel row per object, rendered twice by
// AnnotationItem (on screen + offscreen composite). Undo/redo snapshot the
// whole list (objects are few; simplest correct history).
Item {
    id: root
    required property var cfg

    property alias objects: list
    property color drawColor: root.cfg.palette[4] ?? "#3b82f6"
    property int thickness: root.cfg.drawThickness
    property int counterNext: 1
    property int selectedObj: -1
    property int editingObj: -1
    property var selObjRect: null
    property var undoStack: []
    property var redoStack: []
    // Snapshot taken when a draw/move starts, pushed if it changed anything.
    property var preState: null

    ListModel {
        id: list
    }

    function newRow(type: string): var {
        return {
            type: type,
            colorStr: "" + root.drawColor,
            thickness: root.thickness,
            rx: 0, ry: 0, rw: 0, rh: 0, px2: 0, py2: 0,
            ptsJson: "[]",
            textStr: "",
            n: 0,
            editing: false,
            fontPx: root.cfg.textBaseSize + root.thickness * 3
        };
    }

    function serialize(): var {
        const arr = [];
        for (let i = 0; i < list.count; i++) {
            const r = list.get(i);
            arr.push({
                type: r.type, colorStr: r.colorStr, thickness: r.thickness,
                rx: r.rx, ry: r.ry, rw: r.rw, rh: r.rh, px2: r.px2, py2: r.py2,
                ptsJson: r.ptsJson, textStr: r.textStr, n: r.n, editing: false, fontPx: r.fontPx
            });
        }
        return arr;
    }

    function restore(arr: var): void {
        list.clear();
        for (const r of arr)
            list.append(r);
        root.selectedObj = -1;
        root.selObjRect = null;
        root.editingObj = -1;
    }

    function pushUndo(state: var): void {
        root.undoStack = [...root.undoStack, state];
        root.redoStack = [];
    }

    function undo(): void {
        if (root.undoStack.length === 0)
            return;
        root.redoStack = [...root.redoStack, root.serialize()];
        const stack = [...root.undoStack];
        root.restore(stack.pop());
        root.undoStack = stack;
    }

    function redo(): void {
        if (root.redoStack.length === 0)
            return;
        root.undoStack = [...root.undoStack, root.serialize()];
        const stack = [...root.redoStack];
        root.restore(stack.pop());
        root.redoStack = stack;
    }

    function deleteSelected(): void {
        if (root.selectedObj < 0)
            return;
        root.pushUndo(root.serialize());
        list.remove(root.selectedObj);
        root.selectedObj = -1;
        root.selObjRect = null;
    }

    function counterDiameter(thickness: real): real {
        return root.cfg.counterBaseSize + thickness * 3;
    }

    function bounds(i: int): rect {
        const r = list.get(i);
        switch (r.type) {
        case "rect":
        case "ellipse":
        case "blur":
        case "pixelate":
            return Qt.rect(r.rx, r.ry, r.rw, r.rh);
        case "line":
        case "arrow":
        case "marker":
            return Qt.rect(Math.min(r.rx, r.px2), Math.min(r.ry, r.py2), Math.abs(r.px2 - r.rx), Math.abs(r.py2 - r.ry));
        case "pencil": {
            const pts = JSON.parse(r.ptsJson);
            let x1 = 1e9, y1 = 1e9, x2 = -1e9, y2 = -1e9;
            for (const p of pts) {
                x1 = Math.min(x1, p.x);
                y1 = Math.min(y1, p.y);
                x2 = Math.max(x2, p.x);
                y2 = Math.max(y2, p.y);
            }
            return Qt.rect(x1, y1, Math.max(0, x2 - x1), Math.max(0, y2 - y1));
        }
        case "text":
            return Qt.rect(r.rx, r.ry, Math.max(20, r.textStr.length * r.fontPx * 0.6), r.fontPx * 1.4);
        case "counter": {
            const d = root.counterDiameter(r.thickness);
            return Qt.rect(r.rx - d / 2, r.ry - d / 2, d, d);
        }
        }
        return Qt.rect(0, 0, 0, 0);
    }

    // Topmost object under (x, y), -1 = none.
    function hit(x: real, y: real): int {
        const pad = root.cfg.hitPad;
        for (let i = list.count - 1; i >= 0; i--) {
            const b = root.bounds(i);
            if (x >= b.x - pad && x <= b.x + b.width + pad && y >= b.y - pad && y <= b.y + b.height + pad)
                return i;
        }
        return -1;
    }

    // Thickness change (wheel) also restyles the selected object.
    function setThickness(t: int): void {
        root.thickness = Math.max(1, Math.min(root.cfg.maxThickness, t));
        if (root.selectedObj >= 0) {
            list.setProperty(root.selectedObj, "thickness", root.thickness);
            root.selObjRect = root.bounds(root.selectedObj);
        }
    }
}
