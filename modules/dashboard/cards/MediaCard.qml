import QtQuick
import "../../../components"
import "../../../config"

// Now-playing card (2x2 square, iOS Now Playing widget): the album art,
// heavily blurred and darkened, fills the card; sharp cover top-left,
// play/pause disc top-right, title + artist packed at the bottom. Real
// data from the Players service; the button calls straight into it.
DashboardCard {
    id: root
    required property var players

    // Grid footprint in units, hardcoded here (grid-first).
    readonly property int spanCols: 2
    readonly property int spanRows: 2

    readonly property real _pad: (dash?.cardPadding) ?? 10
    readonly property real _coverSide: Math.round((root.height - 2 * _pad) * 0.44)
    readonly property real _btnSize: Math.round(_coverSide * 0.55)
    readonly property real _titleFs: (dash?.titleSize) ?? 13

    readonly property bool hasTrack: (players?.active) !== null && (players?.active) !== undefined
    readonly property bool playing: (players?.musicActive) ?? false
    readonly property string art: (players?.artUrl) ?? ""
    readonly property string titleStr: root.hasTrack ? ((players?.trackTitle) || I18n.tr("Untitled")) : I18n.tr("Not Playing")
    readonly property string artistStr: root.hasTrack ? ((players?.trackArtist) ?? "") : I18n.tr("Music")

    // Backdrop: blurred art (rounded to the card) + dark scrim for text.
    RoundedImage {
        anchors.fill: parent
        radius: root.radius
        source: root.art
        blur: 1
        visible: root.art !== ""
    }
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: root.art !== ""
        gradient: Gradient {
            GradientStop { position: 0; color: "#59000000" }
            GradientStop { position: 1; color: "#A6000000" }
        }
    }

    Item {
        anchors.fill: parent
        anchors.margins: root._pad

        RoundedImage {
            id: cover
            anchors.left: parent.left
            anchors.top: parent.top
            width: root._coverSide
            height: root._coverSide
            radius: 12
            source: root.art
            fallbackColor: root.theme?.cardTrack ?? "#2C2C2E"
            fallbackGlyph: "♫"
            glyphSize: Math.round(root._coverSide * 0.45)
        }

        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            width: root._btnSize
            height: root._btnSize
            radius: width / 2
            color: playMa.pressed ? "#59FFFFFF" : "#2EFFFFFF"
            visible: root.hasTrack
            opacity: (root.players?.canTogglePlaying) ?? false ? 1 : 0.4

            Text {
                id: playGlyph
                anchors.centerIn: parent
                // Optical centring: the play triangle's mass sits left.
                anchors.horizontalCenterOffset: text === "" ? 1 : 0
                text: root.playing ? "" : ""
                color: "white"
                font.family: root.theme?.iconFamily ?? "tabler-icons"
                font.pixelSize: Math.round(root._btnSize * 0.5)
                // Glyph-swap pop, same as PlayerModule's TransportBtn
                // (user-approved exception to the Spring-only rule):
                // scale dips to 0 on the accel curve, the new glyph swaps
                // in, scale returns on the decel curve.
                Behavior on text {
                    SequentialAnimation {
                        NumberAnimation {
                            target: playGlyph
                            property: "scale"
                            to: 0
                            duration: 133
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.3, 0, 1, 1, 1, 1]
                        }
                        PropertyAction {}
                        NumberAnimation {
                            target: playGlyph
                            property: "scale"
                            to: 1
                            duration: 133
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0, 0, 0, 1, 1, 1]
                        }
                    }
                }
            }
            MouseArea {
                id: playMa
                anchors.fill: parent
                onClicked: root.players?.playPause()
            }
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: 1

            Text {
                width: parent.width
                text: root.titleStr
                color: "white"
                font.pixelSize: root._titleFs
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: root.artistStr
                color: root.theme?.cardDim ?? "#99EBEBF5"
                font.pixelSize: root._titleFs - 1
                elide: Text.ElideRight
                visible: text !== ""
            }
        }
    }
}
