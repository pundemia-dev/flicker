import QtQuick
import "../../../components"

// Glyph + label row of the QS list panels (Wi‑Fi portal sign-in / other
// network / settings, VPN subscription): hover / press plate like a list
// row. `panel` = the panel (pc, theme, frost, pad).
Item {
    id: ar
    property Item panel: null
    property string glyph: ""
    property string label: ""
    property color tint: "white"
    signal clicked
    readonly property var pc: ar.panel?.pc ?? ({})
    readonly property var theme: ar.panel?.theme ?? null
    width: parent?.width ?? 0
    height: ar.pc.rowHeight ?? 42
    Rectangle {
        x: 6
        width: parent.width - 12
        height: parent.height
        radius: height / 2
        color: ar.panel?.frost?.layerColor(ar.theme?.qsDisc ?? "#3A3A3C") ?? (ar.theme?.qsDisc ?? "#3A3A3C")
        opacity: arMa.pressed ? 0.8 : arMa.containsMouse ? 0.45 : 0
        Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
    }
    Icon {
        id: arGlyph
        x: ar.panel?.pad ?? 18
        width: ar.pc.glyphSize ?? 20
        height: parent.height
        text: ar.glyph
        font.family: ar.theme?.iconFamily ?? "tabler-icons"
        iconSize: (ar.pc.glyphSize ?? 20) - 2
        iconColor: ar.tint
    }
    Text {
        x: arGlyph.x + arGlyph.width + 12
        width: parent.width - x - (ar.panel?.pad ?? 18)
        height: parent.height
        verticalAlignment: Text.AlignVCenter
        text: ar.label
        color: ar.tint
        font.pixelSize: ar.pc.textSize ?? 14
        elide: Text.ElideRight
    }
    MouseArea {
        id: arMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: ar.clicked()
    }
}
