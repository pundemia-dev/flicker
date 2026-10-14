import QtQuick
import QtQuick.Shapes
import QtMultimedia
import Quickshell
import Quickshell.Io

// Round lock-screen avatar: a still image, an animated one (GIF / WebP /
// APNG) or a video (muted, looped) — the same media kinds the wallpaper daemon
// takes. Source = `lock.avatar` ("" = ~/.face, ~/.face.icon, AccountsService);
// the kind is the file's MIME type (scripts/lock/avatar.sh — ~/.face has no
// extension). Drawn like components/RoundedImage: a CurveRenderer circle
// filled from a hidden layered wrapper (antialiased edge; MultiEffect masks
// are binary here). Nothing found / not decodable → the user's initial.
Item {
    id: root

    required property var cfg
    property string path: ""
    property string kind: ""
    readonly property bool ready: media.item?.ready ?? false
    // Ready to be shown: the media is up, or there is none / it never came
    // (`avatarWaitMs`) — then the initial disc is the final look. The skin
    // waits for it so the avatar blurs in once, never pops in later.
    property bool resolved: false
    property bool timedOut: false
    readonly property bool settled: root.ready || (root.resolved && root.kind === "") || root.timedOut

    Timer {
        running: !root.ready
        interval: root.cfg.avatarWaitMs ?? 2000
        onTriggered: root.timedOut = true
    }

    implicitWidth: root.cfg.avatarSize ?? 96
    implicitHeight: root.cfg.avatarSize ?? 96

    Process {
        running: true
        command: ["bash", Quickshell.shellDir + "/scripts/lock/avatar.sh", root.cfg.avatar ?? ""]
        stdout: StdioCollector {
            onStreamFinished: {
                root.resolved = true;
                const f = text.trim().split("\t");
                if (f.length === 2) {
                    root.path = f[0];
                    root.kind = f[1];
                }
            }
        }
    }

    // Fill texture: the layer bakes the cropped frame at item size (and every
    // new GIF / video frame).
    Item {
        id: art
        anchors.fill: parent
        visible: false
        layer.enabled: true
        layer.smooth: true

        Loader {
            id: media
            anchors.fill: parent
            sourceComponent: root.kind === "video" ? videoComp : root.kind === "animated" ? animComp : root.kind === "image" ? imageComp : null
        }
    }

    Shape {
        anchors.fill: parent
        visible: root.ready
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillColor: "white"
            fillItem: art

            PathRectangle {
                width: root.width
                height: root.height
                radius: Math.min(root.width, root.height) / 2
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Math.min(width, height) / 2
        color: root.cfg.avatarFallbackColor ?? "#2A2D33"
        visible: !root.ready

        Text {
            anchors.centerIn: parent
            text: (Quickshell.env("USER") ?? "?").charAt(0).toUpperCase()
            color: root.cfg.avatarFallbackInk ?? "#C7D0DE"
            font.pixelSize: parent.height * 0.42
            font.weight: Font.Medium
        }
    }

    Component {
        id: imageComp
        Image {
            readonly property bool ready: status === Image.Ready
            source: "file://" + root.path
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            mipmap: true
            sourceSize: Qt.size(root.width * 2, root.height * 2)
        }
    }

    Component {
        id: animComp
        AnimatedImage {
            readonly property bool ready: status === AnimatedImage.Ready
            source: "file://" + root.path
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            smooth: true
            playing: true
        }
    }

    Component {
        id: videoComp
        Item {
            // First decoded frame on screen (no black disc before it).
            readonly property bool ready: player.playbackState === MediaPlayer.PlayingState && player.position > 0
            MediaPlayer {
                id: player
                source: "file://" + root.path
                loops: MediaPlayer.Infinite
                videoOutput: output
                // No audioOutput: silent.
                Component.onCompleted: play()
            }
            VideoOutput {
                id: output
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectCrop
            }
        }
    }
}
