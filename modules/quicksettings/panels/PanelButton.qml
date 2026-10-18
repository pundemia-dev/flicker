import QtQuick
import "../../../components"

// Small round glyph button of the QS list panels (header refresh, the
// password field's eye): plate on hover / press, `spin` turns the glyph
// (busy) and, when it stops, springs on to the next full turn instead of
// snapping back; a glyph change bumps it.
Item {
    id: root
    property var pc: ({})
    property var theme: null
    property var frost: null
    property string glyph: ""
    property real size: 32
    property bool spin: false
    signal clicked

    width: root.size
    height: root.size

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.frost?.layerColor(root.theme?.qsDisc ?? "#3A3A3C") ?? (root.theme?.qsDisc ?? "#3A3A3C")
        opacity: ma.pressed ? 0.8 : ma.containsMouse ? 0.45 : 0
        Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
    }
    Icon {
        id: icon
        anchors.centerIn: parent
        text: root.glyph
        font.family: root.theme?.iconFamily ?? "tabler-icons"
        iconSize: (root.pc.glyphSize ?? 20) - 2
        iconColor: root.theme?.cardDim ?? "#99EBEBF5"
        scale: bump.value
        onTextChanged: bump.bump()
        GlyphBump {
            id: bump
            peak: 1.18
        }
    }
    RotationAnimation {
        id: spinAnim
        target: icon
        from: 0
        to: 360
        duration: 900
        loops: Animation.Infinite
    }
    Spring {
        id: spinStop
        target: icon
        property: "rotation"
        to: 360
        stiffness: 4
        damp: 0.5
        eps: 0.5
        onStopped: if (!root.spin) icon.rotation = 0
    }
    Component.onCompleted: if (root.spin) spinAnim.start()
    onSpinChanged: {
        if (root.spin) {
            spinStop.stop();
            spinAnim.start();
        } else if (spinAnim.running) {
            spinAnim.stop();
            spinStop.start();
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
