import QtQuick
import "../../../../components"
import "../../../../config"
import "WallSettingsList.js" as Rows

// Settings panel of the wallpaper carousel (Ctrl+I): tabs on top
// (WallSettingsList.PAGES, PgUp/PgDn or a click) and the page's rows in a
// two-column grid below (WallSettingRow); pages swap with the blur-fade.
// Values are services/Wallpaper.cfg (config.json + overrides); a change
// goes through plugin.changeSetting (persisted as an override, config.json
// is never rewritten). Keys come through WallKeys while
// `plugin.settingsOpen`; a click changes a row.
Item {
    id: root
    required property var plugin
    required property var theme
    required property var c
    required property var lc

    readonly property var wallpaper: root.plugin.wallpaper
    readonly property var base: Config.data.launcher?.wallpapers ?? ({})
    readonly property real pad: root.c.settingsPadding ?? 10
    readonly property real gap: root.c.settingsColumnGap ?? 24
    readonly property real tabH: root.c.settingsTabHeight ?? 24

    function valueOf(row: var): var {
        return root.wallpaper?.cfg[row.key];
    }

    function valueText(row: var): string {
        const v = root.valueOf(row);
        if (row.kind === "bool")
            return v ? I18n.tr("On") : I18n.tr("Off");
        if (row.kind !== "choice")
            return "";
        const o = row.options[Rows.optionIndex(row, v ?? "")];
        const t = I18n.tr(o.label);
        return o.arg !== undefined ? t.arg(o.arg) : t;
    }

    // Tabs.
    Row {
        x: root.pad
        y: root.pad / 2
        height: root.tabH
        spacing: root.gap

        Repeater {
            model: Rows.PAGES.length

            Text {
                required property int index
                readonly property bool current: index === root.plugin.settingsPage
                height: root.tabH
                verticalAlignment: Text.AlignVCenter
                text: I18n.tr(Rows.PAGES[index].title)
                color: current ? root.theme.qsBlue : root.theme.cardDim
                font.family: root.theme.fontFamily
                font.pixelSize: root.lc.subFontSize
                font.weight: current ? Font.DemiBold : Font.Normal

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.plugin.setSettingsPage(parent.index)
                }
            }
        }
    }

    Repeater {
        model: Rows.PAGES.length

        FadeBlur {
            id: page
            required property int index
            readonly property var rows: Rows.PAGES[index].rows
            readonly property int perColumn: Math.ceil(page.rows.length / 2)
            readonly property real cellW: (width - root.pad * 2 - root.gap) / 2
            readonly property real cellH: (height - root.pad / 2) / page.perColumn
            y: root.pad / 2 + root.tabH
            width: root.width
            height: root.height - y
            shown: index === root.plugin.settingsPage

            function cellX(i: int): real {
                return root.pad + Math.floor(i / page.perColumn) * (page.cellW + root.gap);
            }
            function cellY(i: int): real {
                return (i % page.perColumn) * page.cellH;
            }

            // Focus plate: springs between the cells.
            Rectangle {
                readonly property int i: Math.min(root.plugin.settingsFocus, page.rows.length - 1)
                x: page.cellX(i) - root.pad / 2
                y: page.cellY(i)
                width: page.cellW + root.pad
                height: page.cellH
                radius: Math.min(height / 2, root.lc.itemRadius ?? 20)
                color: root.theme.cardBg
                Behavior on x { Spring { stiffness: root.lc.motionStiffness ?? 5; damp: root.lc.motionDamping ?? 0.45 } }
                Behavior on y { Spring { stiffness: root.lc.motionStiffness ?? 5; damp: root.lc.motionDamping ?? 0.45 } }
            }

            Repeater {
                model: page.rows.length

                WallSettingRow {
                    required property int index
                    row: page.rows[index]
                    x: page.cellX(index)
                    y: page.cellY(index)
                    width: page.cellW
                    height: page.cellH
                    theme: root.theme
                    c: root.c
                    lc: root.lc
                    value: root.valueOf(row)
                    valueText: root.valueText(row)
                    changed: row.kind !== "reset" && root.wallpaper?.overrides[row.key] !== undefined
                        && root.wallpaper?.overrides[row.key] !== root.base[row.key]
                    onActivated: {
                        root.plugin.settingsFocus = index;
                        root.plugin.changeSetting(index, 1);
                    }
                }
            }
        }
    }
}
