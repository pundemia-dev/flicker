import QtQuick
import QtQuick.Layouts
import "../../../components"

// Now-playing mini card (fills the grid slot next to Updates). Real data
// from the Players service; transport buttons call straight into it.
DashboardCard {
    id: root
    required property var players

    // Grid footprint in units, hardcoded here (grid-first).
    readonly property int spanCols: 4
    readonly property int spanRows: 1

    // Grid-first: transport buttons scale to the allocated height
    // (title + track + gaps eat ~40px), clamped to the classic size.
    readonly property real _innerH: root.height - 2 * ((root.dash?.cardPadding) ?? 10)
    readonly property real _btnSize: Math.max(16, Math.min(28, _innerH - 40))

    readonly property bool hasTrack: (players?.active) !== null && (players?.active) !== undefined

    readonly property string trackStr: {
        if (!root.hasTrack)
            return "Ничего не играет";
        const title = players.trackTitle ?? "";
        const artist = players.trackArtist ?? "";
        if (!title)
            return "No media";
        return artist ? `${title} — ${artist}` : title;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.dash?.cardPadding ?? 10
        spacing: 2

        CardTitle {
            label: "Сейчас играет"
            theme: root.theme
            dash: root.dash
        }
        Text {
            text: root.trackStr
            color: "white"
            font.pixelSize: root.dash?.titleSize ?? 13
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        Item { Layout.fillHeight: true }
        RowLayout {
            spacing: 8
            visible: root.hasTrack

            MediaBtn {
                label: "⏮"
                theme: root.theme
                btnSize: root._btnSize
                onClicked: root.players?.previous()
            }
            MediaBtn {
                label: (root.players?.musicActive) ?? false ? "⏸" : "▶"
                theme: root.theme
                btnSize: root._btnSize
                onClicked: root.players?.playPause()
            }
            MediaBtn {
                label: "⏭"
                theme: root.theme
                btnSize: root._btnSize
                onClicked: root.players?.next()
            }
        }
    }

    component MediaBtn: Rectangle {
        id: btn
        property string label: ""
        property var theme: null
        property real btnSize: 28
        signal clicked

        width: btn.btnSize
        height: btn.btnSize
        radius: btn.btnSize / 2
        color: ma.containsMouse ? "#39414E" : (btn.theme?.cardTrack ?? "#2C2C2E")

        Text {
            anchors.centerIn: parent
            text: btn.label
            color: "#DFE6F2"
            font.pixelSize: 12
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            onClicked: btn.clicked()
        }
    }
}
