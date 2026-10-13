import QtQuick

// Icon tile background (the wallpaper-settings icon look): a dark vertical
// gradient, a touch lighter at the top, with CardRim's light rim. `fill`
// tints it (checked / accent buttons: lighter → darker of that colour);
// `hovered` lifts it with a faint white veil. Children sit on top.
Rectangle {
    id: root
    required property var theme
    // Transparent = the stock dark tile.
    property color fill: "transparent"
    property bool hovered: false
    property real rimWidth: 1

    readonly property bool tinted: root.fill.a > 0
    gradient: Gradient {
        GradientStop {
            position: 0
            color: root.tinted ? Qt.lighter(root.fill, root.theme.iconTileTintLighter) : root.theme.wallSettingsIconTop
        }
        GradientStop {
            position: 1
            color: root.tinted ? Qt.darker(root.fill, root.theme.iconTileTintDarker) : root.theme.wallSettingsIconBottom
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        topLeftRadius: root.topLeftRadius
        color: root.theme.iconTileHover
        opacity: root.hovered ? 1 : 0
        Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.002 } }
    }

    CardRim {
        anchors.fill: parent
        radius: root.radius
        topLeftRadius: root.topLeftRadius
        rimWidth: root.rimWidth
        topColor: root.theme.wallSettingsIconRimTop
        bottomColor: root.theme.wallSettingsIconRimBottom
    }
}
