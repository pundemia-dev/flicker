import QtQuick
import "../../components"

Item {
    id: root
    required property var audio
    required property var players
    required property var network
    required property var bluetooth
    required property var brightness
    required property var notifications
    signal closeRequested

    Column {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        // Toggle row: Wi-Fi, Bluetooth, Hotspot, DND, Mic
        Row {
            width: parent.width
            spacing: 8

            QsToggleTile { label: "Wi‑Fi"; enabledState: root.network.wifiEnabled; onClicked: root.network.toggleWifi() }
            QsToggleTile { label: "BT"; enabledState: root.bluetooth.powered; onClicked: root.bluetooth.toggle() }
            QsToggleTile { label: "Hotspot"; enabledState: root.network.hotspotEnabled; onClicked: root.network.setHotspotEnabled(!root.network.hotspotEnabled) }
            QsToggleTile { label: "DND"; enabledState: root.notifications.doNotDisturb; onClicked: root.notifications.doNotDisturb = !root.notifications.doNotDisturb }
            QsToggleTile { label: "Mic"; enabledState: !root.audio.sourceMuted; onClicked: { root.audio.quiet(); root.audio.toggleSourceMute(); } }
        }

        QsSliderRow {
            width: parent.width
            icon: root.audio.muted ? "🔇" : "🔊"
            value: root.audio.volume
            max: root.audio.maxVolume
            onMoved: v => { root.audio.quiet(); root.audio.setVolume(v); }
        }
        QsSliderRow {
            width: parent.width
            icon: "☀"
            value: root.brightness.brightness
            max: 1
            onMoved: v => { root.brightness.quiet(); root.brightness.setBrightness(v); }
        }

        // Media controls
        Row {
            width: parent.width
            visible: root.players.active !== null
            spacing: 10

            Text {
                id: trackInfo
                width: parent.width - 122
                anchors.verticalCenter: parent.verticalCenter
                text: root.players.trackTitle.length > 0 ? `${root.players.trackTitle} — ${root.players.trackArtist}` : "No media"
                color: "#DCE4EF"
                font.pixelSize: 11
                elide: Text.ElideRight
            }
            QsMediaButton { label: "⏮"; onClicked: root.players.previous() }
            QsMediaButton { label: root.players.musicActive ? "⏸" : "▶"; onClicked: root.players.playPause() }
            QsMediaButton { label: "⏭"; onClicked: root.players.next() }
        }
    }

    component QsToggleTile: Rectangle {
        id: tile
        property string label: ""
        property bool enabledState: false
        signal clicked

        width: (root.width - 20 - 4 * 8) / 5
        height: 44
        radius: 12
        color: tile.enabledState ? "#3D5A99" : "#242A34"
        Behavior on color { ColorAnimation { duration: 140 } }

        Column {
            anchors.centerIn: parent
            spacing: 3
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tile.label
                color: "#E6EBF5"
                font.pixelSize: 10
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 10
                height: 3
                radius: 1.5
                color: tile.enabledState ? "#9DB9F2" : "#4A525F"
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: tile.clicked()
        }
    }

    component QsSliderRow: Row {
        id: row
        property string icon: ""
        property real value: 0
        property real max: 1
        signal moved(real value)

        spacing: 8
        Text {
            text: row.icon
            color: "#DCE4EF"
            font.pixelSize: 12
            width: 18
            anchors.verticalCenter: parent.verticalCenter
        }
        Slider {
            width: row.width - 26
            anchors.verticalCenter: parent.verticalCenter
            value: row.value
            max: row.max
            onValueChangedByUser: v => row.moved(v)
        }
    }

    component QsMediaButton: Rectangle {
        id: btn
        property string label: ""
        signal clicked

        width: 30
        height: 30
        radius: 15
        color: ma.containsMouse ? "#39414E" : "#2A303A"
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
