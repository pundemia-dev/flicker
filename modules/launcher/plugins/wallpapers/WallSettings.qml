import QtQuick
import "../../../../components"
import "../../../../config"
import "WallSettingsList.js" as Rows

// Settings panel of the wallpaper carousel (Ctrl+I): the rows of
// WallSettingsList in a two-column grid inside the carousel's own body.
// Values are services/Wallpaper.cfg (config.json + overrides); a change
// goes to Wallpaper.setSetting (persisted as an override, config.json is
// never rewritten). Keys come through WallKeys while `plugin.settingsOpen`
// (arrows move the focus plate, ←/→/Enter change); a click changes a row.
// A dot marks a value that differs from config.json.
Item {
    id: root
    required property var plugin
    required property var theme
    required property var c
    required property var lc

    readonly property var wallpaper: root.plugin.wallpaper
    readonly property var base: Config.data.launcher?.wallpapers ?? ({})
    readonly property int columns: 2
    readonly property int rowsPerColumn: Math.ceil(Rows.ROWS.length / root.columns)
    readonly property real pad: root.c.settingsPadding ?? 10
    readonly property real gap: root.c.settingsColumnGap ?? 24
    readonly property real cellW: (root.width - root.pad * 2 - root.gap * (root.columns - 1)) / root.columns
    readonly property real cellH: (root.height - root.pad * 2) / root.rowsPerColumn

    function cellX(i: int): real {
        return root.pad + Math.floor(i / root.rowsPerColumn) * (root.cellW + root.gap);
    }
    function cellY(i: int): real {
        return root.pad + (i % root.rowsPerColumn) * root.cellH;
    }

    function valueOf(row: var): var {
        return root.wallpaper?.cfg[row.key];
    }

    function valueText(row: var): string {
        const v = root.valueOf(row);
        if (row.kind === "bool")
            return v ? I18n.tr("On") : I18n.tr("Off");
        if (row.kind !== "choice")
            return "";
        const o = row.options[Rows.optionIndex(row, v)];
        const t = I18n.tr(o.label);
        return o.arg !== undefined ? t.arg(o.arg) : t;
    }


    // Focus plate: springs between the cells.
    Rectangle {
        readonly property int i: root.plugin.settingsFocus
        x: root.cellX(i) - root.pad / 2
        y: root.cellY(i)
        width: root.cellW + root.pad
        height: root.cellH
        radius: Math.min(height / 2, root.lc.itemRadius ?? 20)
        color: root.theme.cardBg
        Behavior on x { Spring { stiffness: root.lc.motionStiffness ?? 5; damp: root.lc.motionDamping ?? 0.45 } }
        Behavior on y { Spring { stiffness: root.lc.motionStiffness ?? 5; damp: root.lc.motionDamping ?? 0.45 } }
    }

    Repeater {
        model: Rows.ROWS.length

        Item {
            id: cell
            required property int index
            readonly property var row: Rows.ROWS[index]
            readonly property bool changed: cell.row.kind !== "reset"
                && root.wallpaper?.overrides[cell.row.key] !== undefined
                && root.wallpaper?.overrides[cell.row.key] !== root.base[cell.row.key]
            x: root.cellX(index)
            y: root.cellY(index)
            width: root.cellW
            height: root.cellH

            // Changed-from-config dot.
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: -width - 3
                width: 5
                height: 5
                radius: 2.5
                color: root.theme.qsBlue
                opacity: cell.changed ? 1 : 0
                Behavior on opacity { Spring { eps: 0.01 } }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: value.left
                anchors.rightMargin: 8
                text: I18n.tr(cell.row.label)
                elide: Text.ElideRight
                color: cell.row.kind === "reset" ? root.theme.accentRed : root.theme.islandFg
                font.family: root.theme.fontFamily
                font.pixelSize: root.lc.subFontSize
            }

            // bool: a small switch on the accent; choice: ‹ value ›.
            Item {
                id: value
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: cell.row.kind === "bool" ? sw.width : (cell.row.kind === "choice" ? choice.implicitWidth : 0)
                height: parent.height

                Rectangle {
                    id: sw
                    visible: cell.row.kind === "bool"
                    readonly property bool on: !!root.valueOf(cell.row)
                    anchors.verticalCenter: parent.verticalCenter
                    width: (root.c.settingsSwitchHeight ?? 20) * 1.75
                    height: root.c.settingsSwitchHeight ?? 20
                    radius: height / 2
                    color: swColor.value
                    SpringColor {
                        id: swColor
                        target: sw.on ? root.theme.qsBlue : root.theme.cardTrack
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
                        Behavior on x { Spring {} }
                    }
                }
                Text {
                    id: choice
                    visible: cell.row.kind === "choice"
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    text: "‹  " + root.valueText(cell.row) + "  ›"
                    color: root.theme.subtleFg
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.lc.subFontSize
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.plugin.settingsFocus = cell.index;
                    root.plugin.changeSetting(cell.index, 1);
                }
            }
        }
    }
}
