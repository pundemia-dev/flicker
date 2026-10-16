import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Widgets
import "../../components"

// Quick Look player of a tray video / audio file: plays with sound at once
// (looped), click on the picture / P = pause. Video: the frame fills the
// body (island fitted to its size via Stash.preview), the control strip
// fades in over a dark gradient on hover / while paused. Audio: a compact
// card (file icon, name, the same strip). Strip = play disc · progress
// (click / drag seeks) · elapsed / total.
Item {
    id: root
    required property string path
    required property bool video
    required property var stash
    required property var cfg
    required property var theme

    // Frame size for the island fit (StashPreview); audio stays 0.
    readonly property real naturalW: root.video ? videoOut.sourceRect.width : 0
    readonly property real naturalH: root.video ? videoOut.sourceRect.height : 0
    readonly property bool playing: player.playbackState === MediaPlayer.PlayingState
    readonly property real fraction: player.duration > 0 ? player.position / player.duration : 0

    function togglePause(): void {
        root.playing ? player.pause() : player.play();
    }

    function clock(ms: real): string {
        const t = Math.max(0, Math.floor(ms / 1000));
        const h = Math.floor(t / 3600), m = Math.floor(t / 60) % 60, s = t % 60;
        const pad = n => String(n).padStart(2, "0");
        return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
    }

    MediaPlayer {
        id: player
        source: root.stash.urlOf(root.path)
        loops: MediaPlayer.Infinite
        audioOutput: AudioOutput {}
        videoOutput: root.video ? videoOut : null
        Component.onCompleted: player.play()
    }

    // ── Video ──
    VideoOutput {
        id: videoOut
        anchors.fill: parent
        visible: root.video
        fillMode: VideoOutput.PreserveAspectFit
    }
    MouseArea {
        id: videoMa
        anchors.fill: parent
        enabled: root.video
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.togglePause()
    }
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: strip.height + 24
        visible: root.video
        opacity: videoMa.containsMouse || stripHover.hovered || !root.playing ? 1 : 0
        Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
        gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.7) }
        }
    }

    // ── Audio card ──
    Row {
        visible: !root.video
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: strip.top
        anchors.bottomMargin: root.cfg.gap
        spacing: root.cfg.gap * 2

        IconImage {
            anchors.verticalCenter: parent.verticalCenter
            implicitSize: 56
            source: Quickshell.iconPath("audio-x-generic", "application-x-generic")
            asynchronous: true
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 56 - parent.spacing
            spacing: 2
            Text {
                width: parent.width
                text: player.metaData.stringValue(MediaMetaData.Title) || root.path.split("/").pop()
                color: root.theme.islandFg
                font.pixelSize: root.theme.fontSizeClock
                font.weight: Font.DemiBold
                elide: Text.ElideMiddle
            }
            Text {
                width: parent.width
                text: player.metaData.stringValue(MediaMetaData.ContributingArtist) || player.metaData.stringValue(MediaMetaData.AlbumArtist)
                visible: text !== ""
                color: root.theme.subtleFg
                font.pixelSize: root.theme.fontSizeBody
                elide: Text.ElideRight
            }
        }
    }

    // ── Control strip ──
    Item {
        id: strip
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.video ? 10 : 0
        height: 30
        opacity: !root.video || videoMa.containsMouse || stripHover.hovered || !root.playing ? 1 : 0
        Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
        HoverHandler {
            id: stripHover
        }

        IconButton {
            id: playBtn
            theme: root.theme
            width: strip.height
            height: strip.height
            glow: false
            glyph: root.playing ? "" : ""
            onClicked: root.togglePause()
        }
        Item {
            id: bar
            anchors.left: playBtn.right
            anchors.leftMargin: 10
            anchors.right: time.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            height: 16
            ProgressBar {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: barMa.containsMouse || barMa.pressed ? 6 : 4
                value: barMa.pressed ? barMa.scrub : root.fraction
                trackColor: Qt.rgba(1, 1, 1, 0.22)
                fillColor: root.theme.islandFg
            }
            MouseArea {
                id: barMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                property real scrub: 0
                function at(x: real): real {
                    return Math.max(0, Math.min(1, x / bar.width));
                }
                onPressed: mouse => barMa.scrub = barMa.at(mouse.x)
                onPositionChanged: mouse => {
                    if (barMa.pressed)
                        barMa.scrub = barMa.at(mouse.x);
                }
                onReleased: {
                    if (player.seekable)
                        player.position = barMa.scrub * player.duration;
                }
            }
        }
        Text {
            id: time
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: `${root.clock(barMa.pressed ? barMa.scrub * player.duration : player.position)} / ${root.clock(player.duration)}`
            color: root.theme.islandFg
            font.pixelSize: root.theme.fontSizeBody
            font.features: { "tnum": 1 }
        }
    }
}
