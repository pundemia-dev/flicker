import QtQuick
import "../../../components"

// Text pill of the QS list panels: Join (`filled`, accent), row action
// chips (`checked` = accent, `danger` = red label, red fill once checked).
// `dim` = shown but not ready (a Join with an empty field), still takes
// the click. Width (a label change: "Forget" → "Forget this network?"),
// fill and dim spring.
Rectangle {
    id: root
    property var pc: ({})
    property var theme: null
    property var frost: null
    property string text: ""
    property bool filled: false
    property bool checked: false
    property bool danger: false
    property bool dim: false
    signal clicked

    readonly property color plate: root.frost?.layerColor(root.theme?.qsDisc ?? "#3A3A3C") ?? (root.theme?.qsDisc ?? "#3A3A3C")
    width: label.implicitWidth + 28
    Behavior on width { Spring { stiffness: 5; damp: 0.55; eps: 0.3 } }
    radius: height / 2
    color: fill.value
    SpringColor {
        id: fill
        target: root.danger && root.checked ? (root.theme?.accentRed ?? "#E4483E")
            : root.filled || root.checked ? (root.theme?.qsBlue ?? "#017EFC") : root.plate
        stiffness: 5
        damping: 0.6
    }
    opacity: root.dim ? 0.5 : 1
    Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
    clip: true
    scale: ma.pressed ? 0.94 : 1
    Behavior on scale { Spring { stiffness: 6; damp: 0.45; eps: 0.002 } }

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: "white"
        opacity: ma.containsMouse && !root.dim ? 0.08 : 0
        Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.005 } }
    }
    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.danger && !root.checked ? (root.theme?.accentRed ?? "#E4483E") : "white"
        font.pixelSize: (root.pc.textSize ?? 14) - 1
        font.weight: root.filled ? Font.DemiBold : Font.Normal
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
