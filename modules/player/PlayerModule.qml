import QtQuick
import Quickshell.Services.Mpris
import "../../components"

// Player module: cover art (shared element target "player"), track info,
// transport controls. Opened from the Music indicator via click/hover.
Item {
    id: root
    required property var players
    signal closeRequested

    readonly property var player: players.active

    Row {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 14

        // Shared element transition target: the album cover.
        Rectangle {
            id: cover
            width: parent.height
            height: parent.height
            radius: 12
            color: "#2B2F36"
            clip: true

            Image {
                anchors.fill: parent
                source: root.players.artUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: source.toString().length > 0
            }
            Text {
                anchors.centerIn: parent
                text: "♫"
                color: "#E8ECF4"
                font.pixelSize: 32
                visible: root.players.artUrl.length === 0
            }
        }

        Column {
            width: parent.width - cover.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Text {
                width: parent.width
                text: root.players.trackTitle.length > 0 ? root.players.trackTitle : "Nothing playing"
                color: "#F0F4FB"
                font.pixelSize: 14
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: root.players.trackArtist
                color: "#98A4B6"
                font.pixelSize: 12
                elide: Text.ElideRight
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 18

                Rectangle {
                    width: 30; height: 30; radius: 15
                    color: prevMa.containsMouse ? "#39414E" : "#2A303A"
                    Text { anchors.centerIn: parent; text: "⏮"; color: "#DFE6F2"; font.pixelSize: 12 }
                    MouseArea {
                        id: prevMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.players.previous()
                    }
                }
                Rectangle {
                    width: 38; height: 38; radius: 19
                    color: playMa.containsMouse ? "#E4E9F2" : "#CFD7E4"
                    Text {
                        anchors.centerIn: parent
                        text: root.player?.playbackState === MprisPlaybackState.Playing ? "⏸" : "▶"
                        color: "#14161A"
                        font.pixelSize: 14
                    }
                    MouseArea {
                        id: playMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.players.playPause()
                    }
                }
                Rectangle {
                    width: 30; height: 30; radius: 15
                    color: nextMa.containsMouse ? "#39414E" : "#2A303A"
                    Text { anchors.centerIn: parent; text: "⏭"; color: "#DFE6F2"; font.pixelSize: 12 }
                    MouseArea {
                        id: nextMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.players.next()
                    }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.closeRequested()
        z: -1
    }
}
