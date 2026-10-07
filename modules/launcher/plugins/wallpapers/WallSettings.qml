import QtQuick
import "../../../../components"
import "../../../../config"
import "WallSettingsList.js" as Rows

// Settings panel of the wallpaper carousel (Ctrl+I), iOS Settings look:
// a segmented control on top (WallSettingsList.PAGES; the thumb springs
// under the current tab; PgUp/PgDn or a click) and the page's rows in two
// grouped cards (left column first, inset hairlines between rows); pages
// swap with the blur-fade. The focus is a soft highlight that springs from
// row to row. Values are services/Wallpaper.cfg (config.json +
// overrides); a change goes through plugin.changeSetting (persisted as an
// override, config.json is never rewritten). Keys come through WallKeys
// while `plugin.settingsOpen`; a click changes a row.
Item {
    id: root
    required property var plugin
    required property var theme
    required property var c
    required property var lc
    readonly property real fontSize: root.c.settingsFontSize ?? 17

    readonly property var wallpaper: root.plugin.wallpaper
    readonly property var base: Config.data.launcher?.wallpapers ?? ({})
    readonly property real pad: root.c.settingsPadding ?? 10
    readonly property real gap: root.c.settingsColumnGap ?? 14
    readonly property real tabH: root.c.settingsTabHeight ?? 30
    readonly property real segW: root.c.settingsSegmentWidth ?? 150
    readonly property real cardR: root.c.settingsCardRadius ?? 16

    function valueOf(row: var): var {
        return root.wallpaper?.cfg[row.key];
    }

    function valueText(row: var): string {
        const v = root.valueOf(row);
        if (row.kind === "bool")
            return v ? I18n.tr("On") : I18n.tr("Off");
        if (row.kind === "action" && row.action === "semanticIndex") {
            const s = root.wallpaper?.semantic;
            if (!s)
                return "";
            if (s.indexing || s.forced)
                return s.total > 0 ? I18n.tr("Stop · %1 / %2").arg(s.done).arg(s.total) : I18n.tr("Stop");
            return I18n.tr("Run now · %1 indexed").arg(s.count);
        }
        if (row.kind !== "choice")
            return "";
        const o = row.options[Rows.optionIndex(row, v ?? "")];
        const t = I18n.tr(o.label);
        return o.arg !== undefined ? t.arg(o.arg) : t;
    }

    // Segmented control.
    Rectangle {
        id: segments
        // Whole pixels everywhere: NativeRendering glyphs and the 1px rims
        // looked shifted / pixelated on half-pixel positions.
        x: Math.round((root.width - width) / 2)
        y: Math.round(root.pad / 2)
        width: root.segW * Rows.PAGES.length + 4
        height: root.tabH
        radius: height / 2
        color: root.theme.cardBg

        Rectangle {
            x: 2 + root.plugin.settingsPage * root.segW
            y: 2
            width: root.segW
            height: parent.height - 4
            radius: height / 2
            color: root.theme.cardTrack
            Behavior on x { Spring { stiffness: 5; damp: 0.5 } }
        }

        Repeater {
            model: Rows.PAGES.length

            Item {
                required property int index
                readonly property bool current: index === root.plugin.settingsPage
                x: 2 + index * root.segW
                width: root.segW
                height: segments.height

                Row {
                    x: Math.round((parent.width - width) / 2)
                    y: Math.round((parent.height - height) / 2)
                    spacing: 6
                    Text {
                        y: Math.round((parent.height - height) / 2)
                        text: Rows.PAGES[parent.parent.index].glyph ?? ""
                        font.family: root.theme.iconFamily
                        font.pixelSize: root.fontSize
                        color: parent.parent.current ? root.theme.islandFg : root.theme.cardDim
                    }
                    Text {
                        y: Math.round((parent.height - height) / 2)
                        text: I18n.tr(Rows.PAGES[parent.parent.index].title)
                        color: parent.parent.current ? root.theme.islandFg : root.theme.cardDim
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.fontSize - 1
                        font.weight: Font.DemiBold
                    }
                }

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
            readonly property real cardW: Math.floor((width - root.pad * 2 - root.gap) / 2)
            readonly property real rowH: root.c.settingsRowHeight ?? 45
            // Gap between the first / last row and the card's edge.
            readonly property real cardPad: root.c.settingsCardPadding ?? 8
            y: Math.round(segments.y + segments.height + root.pad)
            width: root.width
            height: root.height - y
            shown: index === root.plugin.settingsPage

            function column(i: int): int {
                return Math.floor(i / page.perColumn);
            }
            function rowsIn(col: int): int {
                return Math.min(page.perColumn, page.rows.length - col * page.perColumn);
            }

            // The two grouped cards.
            Repeater {
                model: 2
                Rectangle {
                    required property int index
                    x: root.pad + index * (page.cardW + root.gap)
                    width: page.cardW
                    height: page.rowsIn(index) * page.rowH + page.cardPad * 2
                    radius: root.cardR
                    color: root.theme.cardBg
                    visible: page.rowsIn(index) > 0

                    WallCardRim {
                        anchors.fill: parent
                        radius: root.cardR
                        rimWidth: root.c.settingsRimWidth ?? 1
                        topColor: root.theme.wallSettingsRimTop
                        bottomColor: root.theme.wallSettingsRimBottom
                    }
                }
            }

            // Focus highlight: springs between the rows (inside the cards).
            Rectangle {
                readonly property int i: Math.min(root.plugin.settingsFocus, page.rows.length - 1)
                readonly property int col: page.column(i)
                readonly property int r: i - col * page.perColumn
                x: root.pad + col * (page.cardW + root.gap) + 3
                y: page.cardPad + r * page.rowH + 3
                width: page.cardW - 6
                height: page.rowH - 6
                radius: root.cardR - 3
                color: root.theme.wallSettingsFocus
                Behavior on x { Spring { stiffness: root.lc.motionStiffness ?? 5; damp: root.lc.motionDamping ?? 0.45 } }
                Behavior on y { Spring { stiffness: root.lc.motionStiffness ?? 5; damp: root.lc.motionDamping ?? 0.45 } }
            }

            Repeater {
                model: page.rows.length

                WallSettingRow {
                    required property int index
                    readonly property int col: page.column(index)
                    readonly property int r: index - col * page.perColumn
                    row: page.rows[index]
                    x: root.pad + col * (page.cardW + root.gap)
                    y: page.cardPad + r * page.rowH
                    width: page.cardW
                    height: page.rowH
                    separator: r < page.rowsIn(col) - 1
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
