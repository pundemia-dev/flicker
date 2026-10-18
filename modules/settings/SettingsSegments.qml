import QtQuick
import "../../components"
import "../../config"

// iOS segmented control for short choice rows: the selected segment's
// plate springs under it. `options` = [{ value, label }].
Rectangle {
    id: root
    required property var theme
    property var options: []
    property var value
    signal picked(var value)

    // Equal segments, as wide as the widest label (bold, the selected look).
    readonly property real segWidth: Math.ceil(Math.max(40, ...root.options.map(o => metrics.advanceWidth(I18n.tr(o.label))))) + 24

    FontMetrics {
        id: metrics
        font.family: root.theme.fontFamily
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }
    readonly property int current: root.options.findIndex(o => o.value === root.value)

    width: root.segWidth * root.options.length + 4
    height: 30
    radius: 9
    color: root.theme.settingsPressed

    Rectangle {
        visible: root.current >= 0
        x: 2 + root.current * root.segWidth
        y: 2
        width: root.segWidth
        height: parent.height - 4
        radius: 7
        color: root.theme.settingsSecondary
        Behavior on x { Spring { stiffness: 5; damp: 0.55 } }
    }

    Repeater {
        model: root.options

        Text {
            required property var modelData
            required property int index
            x: 2 + index * root.segWidth + (root.segWidth - implicitWidth) / 2
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr(modelData.label)
            color: root.theme.islandFg
            font.family: root.theme.fontFamily
            font.pixelSize: 13
            font.weight: index === root.current ? Font.DemiBold : Font.Normal

            MouseArea {
                x: -(root.segWidth - parent.implicitWidth) / 2
                width: root.segWidth
                height: root.height
                y: (parent.height - root.height) / 2
                cursorShape: Qt.PointingHandCursor
                onClicked: root.picked(modelData.value)
            }
        }
    }
}
