import QtQuick
import "../../../../components"

// Status pill over the carousel top (hidden-files view, slideshow): glyph
// + text on the caption shade, blur-fades in/out and collapses out of the
// row once gone.
FadeBlur {
    id: root
    required property var theme
    required property var c
    required property var lc
    property string glyph: ""
    property string text: ""

    visible: root.p > 0.01
    width: row.implicitWidth + (root.c.badgeSize ?? 26)
    height: root.c.badgeSize ?? 26

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.theme.wallCaptionShade
    }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.glyph
            font.family: root.theme.iconFamily
            font.pixelSize: (root.c.badgeSize ?? 26) * 0.58
            color: root.theme.islandFg
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            font.family: root.theme.fontFamily
            font.pixelSize: root.lc.subFontSize - 2
            font.weight: Font.DemiBold
            color: root.theme.islandFg
        }
    }
}
