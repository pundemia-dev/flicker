import QtQuick
import QtMultimedia
import "../../../../components"
import "../../../../config"
import "CarouselMath.js" as M

// One carousel card. Geometry comes from its offset `d` to the animated
// centre (CarouselMath): width/height/x per d, the art inside is wider than
// the card and shifted against the motion (parallax), so the card reads as
// a window sliding over a slower picture. The thumbnail is the static
// frame; while `playing` (centre card, carousel at rest for playDelayMs) a
// GIF / video fades in over it — muted, looped, destroyed when it stops.
Item {
    id: root
    required property var entry
    required property real d
    required property var c
    required property var lc
    required property var theme
    required property var service
    property bool playing: false
    property bool favourite: false
    // Born in place (a renamed card, a ghost): no rise-in.
    property bool instant: false
    // Ghost of a removed card: dissolves (blur + fade + shrink) as gone → 1.
    property bool leaving: false
    signal clicked

    // FLIP offset (cards): the carousel adds it to d; a rebuild that moved
    // this card sets it to old − new and it springs back to 0.
    property real shift: 0
    Behavior on shift {
        id: shiftBehavior
        Spring {
            stiffness: root.c.closeStiffness ?? 4
            damp: root.c.closeDamping ?? 0.5
            eps: 0.002
        }
    }
    function jumpShift(v: real): void {
        shiftBehavior.enabled = false;
        root.shift = v;
        shiftBehavior.enabled = true;
        root.shift = 0;
    }

    property real gone: 0
    Behavior on gone { Spring { stiffness: root.c.leaveStiffness ?? 3; damp: root.c.leaveDamping ?? 0.6; eps: 0.005 } }

    readonly property real near: M.near(root.d)
    readonly property real halfWidth: (parent?.width ?? 0) / 2

    width: M.width(root.c, root.d)
    height: M.height(root.c, root.d)
    x: root.halfWidth + M.x(root.c, root.d) - root.width / 2
    y: ((parent?.height ?? 0) - root.height) / 2
    z: 100 - Math.abs(root.d)

    // Newcomers (search results, the window growing) rise in.
    property real appear: 0
    Behavior on appear {
        id: appearBehavior
        Spring { stiffness: 4; damp: 0.5; eps: 0.005 }
    }
    Component.onCompleted: {
        if (root.instant || root.leaving) {
            appearBehavior.enabled = false;
            root.appear = 1;
            appearBehavior.enabled = true;
        } else {
            root.appear = 1;
        }
        if (root.leaving)
            root.gone = 1;
    }
    opacity: root.appear * (1 - root.gone) * M.edgeOpacity(root.c, root.d, root.halfWidth)
    scale: (0.9 + 0.1 * root.appear) * (1 - (root.c.leaveShrink ?? 0.15) * root.gone)

    BlurSurface {
        anchors.fill: parent
        amount: root.gone

        RoundedClip {
            anchors.fill: parent
            radius: root.c.cardRadius

            Rectangle {
                anchors.fill: parent
                color: root.theme.cardBg
            }

            Item {
                id: art
                width: M.artWidth(root.c)
                height: root.c.cardHeight
                x: (root.width - width) / 2 + M.artShift(root.c, root.d)
                y: (root.height - height) / 2

                Image {
                    id: thumb
                    anchors.fill: parent
                    source: root.service.thumbUrl(root.entry)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.height: root.c.thumbHeight
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { Spring { eps: 0.01 } }
                }

                Loader {
                    id: live
                    anchors.fill: parent
                    active: root.playing && root.entry.type !== "image"
                    sourceComponent: root.entry.type === "gif" ? gifComp : videoComp
                    opacity: live.item?.ready ? 1 : 0
                    Behavior on opacity { Spring { eps: 0.01 } }
                }
            }

            // Caption on the centre card only.
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: parent.height * 0.45
                opacity: 1 - root.near
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: root.theme.wallCaptionShade }
                }
            }
            Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: root.lc.itemPadding
                spacing: 8
                opacity: 1 - root.near

                Rectangle {
                    visible: root.entry.type !== "image"
                    anchors.verticalCenter: parent.verticalCenter
                    width: badge.implicitWidth + 12
                    height: badge.implicitHeight + 4
                    radius: height / 2
                    color: root.theme.wallBadge
                    Text {
                        id: badge
                        anchors.centerIn: parent
                        text: root.entry.type === "gif" ? "GIF" : I18n.tr("VIDEO")
                        color: root.theme.islandFg
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.lc.subFontSize - 3
                        font.weight: Font.DemiBold
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - (root.entry.type !== "image" ? badge.implicitWidth + 20 : 0)
                    text: root.entry.name
                    elide: Text.ElideRight
                    color: root.theme.islandFg
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.lc.subFontSize
                    font.weight: Font.DemiBold
                }
            }
        }
    }

    // Hidden file (".name"): an eye-off mark in the top-left corner.
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: root.c.badgeInset ?? 8
        width: root.c.badgeSize ?? 26
        height: width
        radius: width / 2
        color: root.theme.wallCaptionShade
        opacity: root.entry.hidden ? 1 : 0
        scale: root.entry.hidden ? 1 : 0.6
        Behavior on opacity { Spring { eps: 0.01 } }
        Behavior on scale { Spring { stiffness: 5; damp: 0.35; eps: 0.005 } }
        Text {
            anchors.centerIn: parent
            text: "\uecf0" // tabler eye-off
            font.family: root.theme.iconFamily
            font.pixelSize: parent.width * 0.58
            color: root.theme.islandFg
        }
    }

    // Favourite mark: a star on a dark disc in the top-right corner, pops in.
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: root.c.badgeInset ?? 8
        width: root.c.badgeSize ?? 26
        height: width
        radius: width / 2
        color: root.theme.wallCaptionShade
        opacity: root.favourite ? 1 : 0
        scale: root.favourite ? 1 : 0.6
        Behavior on opacity { Spring { eps: 0.01 } }
        Behavior on scale { Spring { stiffness: 5; damp: 0.35; eps: 0.005 } }
        Text {
            anchors.centerIn: parent
            text: "\uf6a6" // tabler star-filled
            font.family: root.theme.iconFamily
            font.pixelSize: parent.width * 0.58
            color: root.theme.accentYellow
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    Component {
        id: gifComp
        AnimatedImage {
            readonly property bool ready: status === AnimatedImage.Ready
            source: "file://" + root.entry.path
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            playing: true
        }
    }

    Component {
        id: videoComp
        Item {
            // First decoded frame on screen (no black flash over the thumb).
            readonly property bool ready: player.playbackState === MediaPlayer.PlayingState && player.position > 0
            MediaPlayer {
                id: player
                source: "file://" + root.entry.path
                loops: MediaPlayer.Infinite
                videoOutput: output
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
