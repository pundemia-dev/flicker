import QtQuick
import "../../components"

// Round timer button (iOS Clock look): tinted disc + glyph in the tint.
// With a `label` it is a pill with that text instead (the setup's "Start
// timer"); width springs between pill and disc, the label blur-fades.
// `cross` draws a rounded ✕ instead of a font glyph (cancel). Colours
// spring (SpringColor), the glyph swaps with a scale pop; a press dims the
// disc. Disabled = faded, no clicks.
Item {
    id: root
    property real size: 52
    property string glyph: ""
    property string family: "tabler-icons"
    property real glyphSize: 22
    property bool cross: false
    property color disc: "#3A3A3C"
    property color ink: "#FFFFFF"
    property bool enabledState: true
    // Appearance factor (0..1, may follow a spring): fades and grows the
    // button in. Separate from the disabled fade, which has its own spring.
    property real appear: 1
    property string label: ""
    property string labelFamily: "SF Pro Display"
    property real labelSize: 15
    property real labelPad: 18
    signal clicked

    // Last non-empty label, kept while it fades out.
    property string heldLabel: ""
    onLabelChanged: if (root.label !== "") root.heldLabel = root.label
    Component.onCompleted: root.heldLabel = root.label
    width: root.label !== "" ? Math.max(root.size, labelText.implicitWidth + 2 * root.labelPad) : root.size
    Behavior on width { Spring { stiffness: 3.5; damp: 0.5; eps: 0.2 } }
    height: root.size
    Behavior on height { Spring { stiffness: 3.5; damp: 0.5; eps: 0.2 } }
    property real dim: root.enabledState ? 1 : 0.4
    Behavior on dim { Spring { stiffness: 4; damp: 0.6; eps: 0.005 } }
    opacity: root.dim * Math.max(0, Math.min(1, root.appear))
    scale: 0.6 + 0.4 * Math.max(0, root.appear)

    SpringColor { id: discColor; target: root.disc; stiffness: 3; damping: 0.7 }
    SpringColor { id: inkColor; target: root.ink; stiffness: 3; damping: 0.7 }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: discColor.value
        scale: ma.pressed ? 0.92 : 1
        Behavior on scale { Spring { stiffness: 6; damp: 0.45; eps: 0.005 } }
        opacity: ma.pressed ? 0.75 : 1
    }

    Text {
        id: glyphText
        anchors.centerIn: parent
        visible: !root.cross
        text: root.glyph
        color: inkColor.value
        font.family: root.family
        font.pixelSize: root.glyphSize
        // Glyph swap pop (TransportBtn pattern, user-approved exception).
        Behavior on text {
            SequentialAnimation {
                NumberAnimation { target: glyphText; property: "scale"; to: 0; duration: 120; easing.type: Easing.InQuad }
                PropertyAction {}
                NumberAnimation { target: glyphText; property: "scale"; to: 1; duration: 140; easing.type: Easing.OutBack }
            }
        }
    }

    FadeBlur {
        anchors.centerIn: parent
        width: labelText.implicitWidth
        height: labelText.implicitHeight
        shown: root.label !== ""
        Text {
            id: labelText
            text: root.heldLabel
            color: inkColor.value
            font.family: root.labelFamily
            font.pixelSize: root.labelSize
            font.weight: Font.DemiBold
        }
    }

    // Drawn ✕: two rounded bars.
    Repeater {
        model: root.cross ? [45, -45] : []
        delegate: Rectangle {
            required property var modelData
            anchors.centerIn: parent
            width: root.glyphSize * 0.95
            height: Math.max(2, root.glyphSize * 0.16)
            radius: height / 2
            rotation: modelData
            color: inkColor.value
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        onClicked: if (root.enabledState)
            root.clicked()
    }
}
