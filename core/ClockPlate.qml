import QtQuick
import "../components"

// Clock area: normally shows the time; while recording or hotspot is active a
// coloured plate flies in from above (scale 0.5 -> 1), shows a stop/hotspot
// icon, then fades to the elapsed time (recording) / the clock (hotspot). Clicking the plate opens the
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

    // Plate label: recording = elapsed time, hotspot = the clock (spec: same
    // mechanics as recording, time on the plate). A hidden plate carries no
    // text (it would size the plate and widen the bar); while flying away it
    // keeps the last label so it does not shrink mid-exit.
    readonly property string plateLabel: root.rec ? (root.recorder?.elapsedText ?? "") : root.hot ? root.clock.time : ""
    property string heldLabel: ""
    onPlateLabelChanged: if (root.active) root.heldLabel = root.plateLabel

    // Shared element contracts (core/TransitionLayer), per target module.
    // Not offered while the recording/hotspot plate replaces the clock face.
    //  - notifications: the time flies into the flow card's "time" slot and
    //    becomes that card's arrival time (text/colour/size from the slot).
    //  - dashboard: flies into the header's time and grows to its size;
    //    text is NOT in the contract, so the label's live binding keeps
    //    ticking while docked.
    //  - timer: flies into the timer's time (setup value / countdown) and
    //    hides there — the module rolls its own digits (hideLanded); on
    //    close the countdown flies back and turns into the clock.
    readonly property Item sharedElement: clockLabel
    readonly property var sharedTransitions: ({
            notifications: {
                target: "notifications",
                slot: "time",
                properties: {
                    text: "slot",
                    color: "slot",
                    "font.pixelSize": "slot",
                    "font.weight": "slot"
                },
                curve: "spring"
            },
            timer: {
                target: "timer",
                slot: "time",
                properties: {
                    text: "slot",
                    color: "slot",
                    "font.pixelSize": "slot",
                    "font.weight": "slot",
                    "font.family": "slot"
                },
                curve: "spring",
                hideLanded: true
            },
            dashboard: {
                target: "dashboard",
                slot: "time",
                properties: {
                    color: "slot",
                    "font.pixelSize": "slot",
                    "font.weight": "slot"
                },
                curve: "spring"
            }
        })
    // Exact home box (the label's natural box, centred) + live home values,
    // so the return flight lands on the CURRENT time, not the launch one.
    readonly property Item sharedHome: labelHome
    readonly property var sharedHomeValues: ({
            text: root.clock.time,
            color: root.theme.islandFg,
            "font.pixelSize": root.theme.fontSizeClock,
            "font.weight": Font.Medium
        })
    function restoreShared(): void {
        clockLabel.anchors.centerIn = root;
        clockLabel.width = Qt.binding(() => clockLabel.implicitWidth);
        clockLabel.height = Qt.binding(() => clockLabel.implicitHeight);
        clockLabel.text = Qt.binding(() => root.clock.time);
        clockLabel.color = Qt.binding(() => root.theme.islandFg);
        clockLabel.font.pixelSize = Qt.binding(() => root.theme.fontSizeClock);
        clockLabel.font.weight = Font.Medium;
    }

    Item {
        id: labelHome
        anchors.centerIn: parent
        width: clockLabel.implicitWidth
        height: clockLabel.implicitHeight
    }

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
            text: root.active ? root.plateLabel : plate.visible ? root.heldLabel : ""
            opacity: root.showIcon ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.requestModule(root.rec ? "recording-actions" : "hotspot-actions")
        }
    }
}
