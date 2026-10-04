import QtQuick

// Radial colour picker (flameshot RMB wheel, port of pShell ColorWheel):
// swatches in a ring around where it was summoned (RMB or the toolbar
// swatch). Click a swatch to pick; a click elsewhere / Esc closes (editor).
Item {
    id: root
    required property var editor

    readonly property var cfg: root.editor.cfg
    readonly property var swatches: root.cfg.palette
    readonly property real d: root.cfg.paletteSwatch
    readonly property real ringR: Math.max(root.d * 1.8, (root.swatches.length * (root.d + root.cfg.toolSpacing)) / (2 * Math.PI))
    // Keep the whole ring on screen near an edge.
    readonly property real cx: Math.max(root.ringR + root.d / 2, Math.min(root.width - root.ringR - root.d / 2, root.editor.palettePos.x))
    readonly property real cy: Math.max(root.ringR + root.d / 2, Math.min(root.height - root.ringR - root.d / 2, root.editor.palettePos.y))

    visible: root.editor.paletteOpen

    Repeater {
        model: root.swatches

        Rectangle {
            id: swatch
            required property var modelData
            required property int index
            readonly property real ang: -Math.PI / 2 + index * 2 * Math.PI / root.swatches.length
            readonly property bool current: Qt.colorEqual(root.editor.model.drawColor, modelData)
            x: root.cx + root.ringR * Math.cos(ang) - width / 2
            y: root.cy + root.ringR * Math.sin(ang) - height / 2
            width: root.d
            height: root.d
            radius: root.d / 2
            color: modelData
            border.width: current ? 2 : 1
            border.color: current ? root.editor.theme.islandFg : root.editor.theme.cardTrack
            scale: ma.containsMouse ? 1.25 : 1
            Behavior on scale { NumberAnimation { duration: root.cfg.fadeOutMs } }

            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.editor.model.drawColor = swatch.modelData;
                    root.editor.paletteOpen = false;
                }
            }
        }
    }
}
