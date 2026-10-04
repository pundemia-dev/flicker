import QtQuick

// Passive visuals of the region editor: selection frame + physical size
// readout + 8 resize handles, the smart-region candidate under the cursor,
// the selected-object outline and the thickness hint bubble.
Item {
    id: root
    required property var editor

    readonly property var ed: root.editor
    readonly property var theme: root.editor.theme
    readonly property var cfg: root.editor.cfg

    function handlePos(i: int): point {
        const e = root.ed;
        const xs = [e.selX, e.selX + e.selW / 2, e.selX + e.selW];
        const ys = [e.selY, e.selY + e.selH / 2, e.selY + e.selH];
        const map = [[0, 0], [1, 0], [2, 0], [0, 1], [2, 1], [0, 2], [1, 2], [2, 2]];
        return Qt.point(xs[map[i][0]], ys[map[i][1]]);
    }

    Rectangle {
        readonly property var r: root.ed.smartHover
        visible: r !== null && root.ed.dragMode === ""
        x: r?.x ?? 0
        y: r?.y ?? 0
        width: r?.width ?? 0
        height: r?.height ?? 0
        radius: root.cfg.toolRadius / 2
        color: Qt.alpha(root.theme.cardBlue, 0.1)
        border.width: 1
        border.color: Qt.alpha(root.theme.cardBlue, 0.7)
    }

    Rectangle {
        visible: root.ed.selVisible
        x: root.ed.selX
        y: root.ed.selY
        width: root.ed.selW
        height: root.ed.selH
        color: "transparent"
        border.width: root.cfg.selectionBorder
        border.color: root.theme.captureSelection
    }

    Rectangle {
        visible: root.ed.selVisible
        x: Math.max(0, Math.min(root.ed.selX + root.ed.selW - width, root.width - width))
        y: Math.min(root.ed.selY + root.ed.selH + root.cfg.toolSpacing, root.height - height)
        width: dims.implicitWidth + root.cfg.panelPad
        height: dims.implicitHeight + root.cfg.toolSpacing
        radius: height / 2
        color: root.theme.islandBg

        Text {
            id: dims
            anchors.centerIn: parent
            color: root.theme.islandFg
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fontSizeIndicator
            font.features: { "tnum": 1 }
            text: `${Math.round(root.ed.selW * root.ed.dpr)} × ${Math.round(root.ed.selH * root.ed.dpr)}`
        }
    }

    Repeater {
        model: 8

        Rectangle {
            required property int index
            readonly property point p: root.handlePos(index)
            visible: root.ed.hasSelection && root.ed.activeTool === "" && (root.ed.dragMode === "" || root.ed.dragMode === "resize")
            x: p.x - width / 2
            y: p.y - height / 2
            width: root.cfg.handleSize
            height: width
            radius: width / 2
            color: root.theme.captureSelection
            border.width: 1
            border.color: root.theme.islandBg
        }
    }

    Rectangle {
        readonly property var r: root.ed.model.selObjRect
        readonly property real pad: root.cfg.hitPad
        visible: root.ed.model.selectedObj >= 0 && r !== null
        x: (r?.x ?? 0) - pad
        y: (r?.y ?? 0) - pad
        width: (r?.width ?? 0) + pad * 2
        height: (r?.height ?? 0) + pad * 2
        radius: pad
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(root.theme.captureSelection, 0.8)
    }

    Rectangle {
        visible: root.ed.thicknessHintShown
        x: root.ed.cursorX + root.cfg.toolSpacing * 2
        y: root.ed.cursorY - height - root.cfg.toolSpacing * 2
        width: hint.implicitWidth + root.cfg.panelPad
        height: hint.implicitHeight + root.cfg.toolSpacing
        radius: height / 2
        color: root.theme.islandBg

        Text {
            id: hint
            anchors.centerIn: parent
            color: root.theme.islandFg
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fontSizeIndicator
            text: `${root.ed.model.thickness} px`
        }
    }
}
