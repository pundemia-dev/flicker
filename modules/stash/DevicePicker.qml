import QtQuick
import "../../components"
import "../../config"

// LocalSend target picker (pShell DevicePicker port): header (state +
// rescan, which spins while scanning), device rows (wheel-scroll past
// cfg.visibleDevicesMax) or, while uploading, an indeterminate bar.
Item {
    id: root
    required property var localSend
    required property var cfg
    required property var theme
    required property real tileRadius

    readonly property string phase: root.localSend.phase
    readonly property bool sending: root.phase === "sending"
    readonly property int fileCount: root.localSend.pendingFiles.length

    Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.cfg.pickerHeaderHeight

        Text {
            id: headGlyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.sending ? "" : ""
            color: root.theme.cardBlue
            font.family: root.theme.iconFamily
            font.pixelSize: 18
        }
        Text {
            anchors.left: headGlyph.right
            anchors.leftMargin: 8
            anchors.right: rescan.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: root.phase === "scanning" ? I18n.tr("Searching for devices…")
                : root.sending ? I18n.tr("Sending…")
                : root.localSend.devices.count === 0 ? I18n.tr("No devices found")
                : root.fileCount > 1 ? I18n.tr("Send files (%1)").arg(root.fileCount) : I18n.tr("Send to")
            color: root.theme.islandFg
            font.pixelSize: root.theme.fontSizeClock
            font.weight: Font.DemiBold
        }

        IconButton {
            id: rescan
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            theme: root.theme
            width: root.cfg.pickerHeaderHeight
            height: root.cfg.pickerHeaderHeight
            disabled: root.sending
            onClicked: root.localSend.rescan()

            // Spring-driven spin: a full turn per tick while scanning, so it
            // accelerates, settles and waits (pShell's "thinking" rhythm).
            Text {
                anchors.centerIn: parent
                text: ""
                color: root.theme.islandFg
                font.family: root.theme.iconFamily
                font.pixelSize: 16
                rotation: spin.turns * -360
                Behavior on rotation { Spring { stiffness: 3; damp: 0.5; eps: 0.5 } }
            }
            Timer {
                id: spin
                property int turns: 0
                interval: 1100
                repeat: true
                triggeredOnStart: true
                running: root.phase === "scanning"
                onTriggered: spin.turns += 1
            }
        }
    }

    // ── Device list ──
    Item {
        id: viewport
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.topMargin: root.cfg.gap
        anchors.bottom: parent.bottom
        clip: true
        visible: !root.sending

        readonly property real maxScroll: Math.max(0, list.height - viewport.height)
        property real scroll: 0

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 2;
                viewport.scroll = Math.max(0, Math.min(viewport.maxScroll, viewport.scroll - delta));
            }
        }

        Column {
            id: list
            width: parent.width
            y: -scrollY
            spacing: 4
            property real scrollY: viewport.scroll
            Behavior on scrollY { Spring { stiffness: 6; damp: 0.6 } }

            Repeater {
                model: root.localSend.devices

                DeviceUnit {
                    width: list.width
                    height: root.cfg.deviceRowHeight
                    theme: root.theme
                    radius: Math.max(6, root.tileRadius - 4)
                    onPicked: ip => root.localSend.sendTo(ip)
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: root.phase === "ready" && root.localSend.devices.count === 0
            text: I18n.tr("Open LocalSend on another device")
            color: root.theme.subtleFg
            font.pixelSize: root.theme.fontSizeBody
        }
    }

    // ── Upload: indeterminate bar ──
    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.topMargin: root.cfg.gap
        anchors.bottom: parent.bottom
        visible: root.sending

        Rectangle {
            id: track
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 4
            radius: 2
            clip: true
            color: Qt.alpha(root.theme.cardBlue, 0.22)

            Rectangle {
                id: chunk
                width: track.width * 0.38
                height: track.height
                radius: 2
                color: root.theme.cardBlue
                property bool atEnd: false
                x: chunk.atEnd ? track.width - chunk.width : 0
                Behavior on x { Spring { stiffness: 2; damp: 0.3 } }
            }
            Timer {
                interval: 900
                repeat: true
                running: root.sending
                onTriggered: chunk.atEnd = !chunk.atEnd
            }
        }
        Text {
            anchors.top: track.bottom
            anchors.topMargin: 8
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.fileCount > 1 ? I18n.tr("Uploading files (%1)…").arg(root.fileCount) : I18n.tr("Uploading file…")
            color: root.theme.subtleFg
            font.pixelSize: root.theme.fontSizeBody
        }
    }
}
