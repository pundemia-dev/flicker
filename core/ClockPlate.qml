import QtQuick
import "../components"

// Clock area: normally shows the time; while recording or hotspot is active a
// coloured plate flies in from above (scale 0.5 -> 1), shows a stop/hotspot
// icon, then fades to the elapsed time. Clicking the plate opens the
// cancel/stop action buttons. The island itself never changes size.
// The clock face has no MouseArea of its own: presses fall through to the
// gesture layer underneath, which drives the dashboard drawer drag.
Item {
    id: root
    required property var clock
    required property var recorder
    required property var network
    required property var theme
    required property real islandHeight
    required property var cfg
    required property var timingCfg
    signal requestModule(string name)

    readonly property bool rec: root.recorder?.recording ?? false
    readonly property bool hot: !root.rec && (root.network?.hotspotEnabled ?? false)
    readonly property bool active: root.rec || root.hot
    readonly property color plateColor: root.rec ? root.theme.accentRed : root.theme.accentGreen

    property bool showIcon: false

    implicitWidth: Math.max(clockLabel.implicitWidth, plate.width)
    implicitHeight: Math.max(clockLabel.implicitHeight, plate.height)

    onActiveChanged: {
        if (root.active) {
            root.showIcon = true;
            iconTimer.restart();
        } else {
            iconTimer.stop();
            root.showIcon = false;
        }
    }

    Timer {
        id: iconTimer
        interval: root.timingCfg.plateIconMs
        onTriggered: root.showIcon = false
    }

    Text {
        id: clockLabel
        anchors.centerIn: parent
        text: root.clock.time
        color: root.theme.islandFg
        font.pixelSize: root.theme.fontSizeClock
        font.weight: Font.Medium
        opacity: root.active ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 130 } }
    }

    Rectangle {
        id: plate
        anchors.centerIn: parent
        width: Math.max(plateText.implicitWidth + root.cfg.plateHPad, root.cfg.plateMinWidth)
        height: root.cfg.plateHeight
        radius: root.cfg.plateRadius
        color: root.plateColor
        opacity: root.active ? 1 : 0
        scale: root.active ? 1 : 0.5
        visible: opacity > 0.01

        transform: Translate {
            y: root.active ? 0 : -root.islandHeight
            Behavior on y { Spring {} }
        }

        Behavior on opacity { NumberAnimation { duration: 140 } }
        Behavior on scale { Spring {} }
        Behavior on width { Spring {} }

        Text {
            anchors.centerIn: parent
            text: root.rec ? "■" : "◉"
            color: root.theme.islandFg
            font.pixelSize: root.theme.fontSizeIndicator
            opacity: root.showIcon ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }

        Text {
            id: plateText
            anchors.centerIn: parent
            color: root.theme.islandFg
            font.pixelSize: root.theme.fontSizeIndicator
            font.weight: Font.Medium
            text: root.rec ? root.recorder.elapsedText : "Hotspot"
            opacity: root.showIcon ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.requestModule(root.rec ? "recording-actions" : "hotspot-actions")
        }
    }
}
