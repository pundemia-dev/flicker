import QtQuick
import "../../../../components"
import "../../../../config"

// One row of the wallpaper settings panel (iOS Settings look): a dark
// rounded-square icon tile with the glyph in the row's tint, the label, and on the right the value —
// choice = text + selector glyph, bool = a switch, reset = a red label
// only. A dot before the value marks a setting changed from config.json.
// A click = `activated` (the panel steps the value). The hairline under
// the row (`separator`) starts after the icon, like an iOS inset list.
Item {
    id: root
    required property var row
    required property var theme
    required property var c
    required property var lc
    readonly property real fontSize: root.c.settingsFontSize ?? 17
    property var value: null
    property string valueText: ""
    property bool changed: false
    property bool separator: true
    signal activated

    readonly property real inset: root.c.settingsRowInset ?? 12
    // Icon tile size matched to the row's parity so it centres on whole
    // pixels (34 in a 45 px row left 5 / 6 px: the tile sat 1 px low).
    readonly property real iconBase: root.c.settingsIconSize ?? 24
    readonly property real icon: root.iconBase + ((Math.round(root.height) - root.iconBase) % 2 === 0 ? 0 : 1)
    readonly property bool isReset: root.row.kind === "reset"

    // Icon tile.
    Rectangle {
        id: tile
        x: Math.round(root.inset)
        y: Math.floor((root.height - root.icon) / 2)
        width: root.icon
        height: root.icon
        radius: root.icon * 0.28
        // Dark, a touch lighter at the top, with the cards' light rim.
        gradient: Gradient {
            GradientStop { position: 0; color: root.theme.wallSettingsIconTop }
            GradientStop { position: 1; color: root.theme.wallSettingsIconBottom }
        }
        WallCardRim {
            anchors.fill: parent
            radius: tile.radius
            rimWidth: root.c.settingsRimWidth ?? 1
            topColor: root.theme.wallSettingsIconRimTop
            bottomColor: root.theme.wallSettingsIconRimBottom
        }
        // CurveRendering: vector-antialiased glyph — NativeRendering hinted
        // the icon font into blocky strokes at this size.
        Text {
            // Vector glyph: an exact (fractional) centre, no pixel snap.
            x: (tile.width - implicitWidth) / 2
            y: (tile.height - implicitHeight) / 2
            renderType: Text.CurveRendering
            text: root.row.glyph ?? ""
            font.family: root.theme.iconFamily
            font.pixelSize: root.icon * 0.62
            color: root.theme[root.row.tint] ?? root.theme.qsBlue
        }
    }

    Text {
        y: Math.round((root.height - implicitHeight) / 2)
        anchors.left: tile.right
        anchors.leftMargin: root.inset * 0.8
        anchors.right: valueBox.left
        anchors.rightMargin: 8
        text: I18n.tr(root.row.label)
        elide: Text.ElideRight
        color: root.isReset ? root.theme.accentRed : root.theme.islandFg
        font.family: root.theme.fontFamily
        font.pixelSize: root.fontSize
    }

    Item {
        id: valueBox
        anchors.right: parent.right
        anchors.rightMargin: root.inset
        width: root.row.kind === "bool" ? sw.width : (root.row.kind === "choice" ? choiceRow.implicitWidth : 0)
        height: parent.height

        // Changed-from-config dot, just left of the value.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.left
            anchors.rightMargin: 6
            width: 5
            height: 5
            radius: 2.5
            color: root.theme.qsBlue
            opacity: root.changed ? 1 : 0
            Behavior on opacity { Spring { eps: 0.01 } }
        }

        Row {
            id: choiceRow
            visible: root.row.kind === "choice"
            anchors.right: parent.right
            y: Math.round((parent.height - height) / 2)
            spacing: 4
            Text {
                y: Math.round((parent.height - height) / 2)
                text: root.valueText
                color: root.theme.subtleFg
                font.family: root.theme.fontFamily
                font.pixelSize: root.fontSize
            }
            Text {
                y: Math.round((parent.height - height) / 2)
                text: "" // tabler selector
                color: root.theme.cardDim
                font.family: root.theme.iconFamily
                font.pixelSize: root.fontSize
            }
        }

        // iOS-style switch: track tint springs, the knob slides.
        Rectangle {
            id: sw
            visible: root.row.kind === "bool"
            readonly property bool on: !!root.value
            y: Math.round((parent.height - height) / 2)
            anchors.right: parent.right
            height: root.c.settingsSwitchHeight ?? 22
            width: height * 1.7
            radius: height / 2
            color: swColor.value
            SpringColor {
                id: swColor
                target: sw.on ? root.theme.qsGreen : root.theme.cardTrack
                stiffness: 5
                damping: 0.6
            }
            Rectangle {
                width: parent.height - 4
                height: width
                radius: width / 2
                y: 2
                x: sw.on ? parent.width - width - 2 : 2
                color: root.theme.islandFg
                Behavior on x { Spring { stiffness: 6; damp: 0.5 } }
            }
        }
    }

    // Inset hairline.
    Rectangle {
        visible: root.separator
        anchors.bottom: parent.bottom
        x: tile.x + tile.width + root.inset * 0.8
        width: parent.width - x
        height: root.lc.dividerWidth ?? 1
        color: root.theme.launcherDivider
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
