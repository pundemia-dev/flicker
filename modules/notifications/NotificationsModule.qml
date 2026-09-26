import QtQuick

// Two modes in one module (spec): "flow" replaces the bar content with a single
// incoming notification; "center" is the history browser — compact configurable
// stripes ordered by arrival, click one to expand its full content.
Item {
    id: root
    required property var payload
    required property var notificationsService
    required property var cfg
    signal closeRequested

    readonly property bool centerMode: (root.payload?.mode ?? "") === "center"
    readonly property var item: root.payload?.notification ?? null
    property var expanded: null

    // ── Flow mode: the incoming notification ──
    Column {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 6
        visible: !root.centerMode

        Text {
            text: root.item?.appName ?? "Notification"
            color: "#98A4B6"
            font.pixelSize: 11
        }
        Text {
            width: parent.width
            text: root.item?.summary ?? ""
            color: "#F0F4FB"
            font.pixelSize: 13
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            text: root.item?.body ?? ""
            color: "#C0CAD8"
            font.pixelSize: 11
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }
    }

    // ── Center mode: stripe history + expanded detail ──
    Item {
        anchors.fill: parent
        visible: root.centerMode

        Row {
            id: stripeRow
            anchors.fill: parent
            anchors.margins: 10
            anchors.bottomMargin: root.expanded ? 96 : 10
            spacing: 4

            Repeater {
                model: root.notificationsService.history

                Rectangle {
                    required property var modelData
                    width: root.cfg.centerStripeWidth
                    height: root.cfg.centerStripeHeight
                    radius: height / 2
                    color: ma.containsMouse ? "#6E8BD6" : "#4A5464"
                    anchors.verticalCenter: parent.verticalCenter

                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        onClicked: root.expanded = (root.expanded === modelData ? null : modelData)
                    }
                }
            }
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 10
            spacing: 4
            visible: root.expanded !== null

            Text {
                text: root.expanded?.appName ?? ""
                color: "#98A4B6"
                font.pixelSize: 11
            }
            Text {
                width: parent.width
                text: root.expanded?.summary ?? ""
                color: "#F0F4FB"
                font.pixelSize: 13
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: root.expanded?.body ?? ""
                color: "#C0CAD8"
                font.pixelSize: 11
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }
    }
}
