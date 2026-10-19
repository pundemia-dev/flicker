import QtQuick
import Quickshell
import "../../components"
import "../../config"
import "SettingsSchema.js" as Schema

// Left column: "Settings" title, search field, the sections in clusters
// (iOS), and the config file button at the bottom (end-4: click opens
// config.json, right click copies its path). `rail` = narrow window: icons
// only, the search field becomes a button that expands the sidebar over
// the content card (SettingsWindow.railExpanded).
Rectangle {
    id: root
    required property var host
    required property var theme
    property bool rail: false

    readonly property real fullWidth: 272
    readonly property real railWidth: 72
    readonly property real pad: 12
    readonly property real rowHeight: 44
    readonly property real rowGap: 2
    readonly property real clusterGap: 21
    readonly property string configPath: `${Quickshell.shellDir}/config/config.json`

    width: root.rail ? root.railWidth : root.fullWidth
    Behavior on width { Spring { stiffness: 6; damp: 0.65 } }
    color: root.theme.settingsBg
    clip: true

    // Top of a section's row in the list (fixed row heights, so no layout
    // pass is needed); -1 = not in the sidebar.
    function rowY(id: string): real {
        let y = 0;
        for (const cluster of Schema.SIDEBAR) {
            const i = cluster.findIndex(s => s.id === id);
            if (i >= 0)
                return y + i * (root.rowHeight + root.rowGap);
            y += cluster.length * (root.rowHeight + root.rowGap) - root.rowGap + root.clusterGap;
        }
        return -1;
    }

    function focusSearch(): void {
        if (root.host.compact)
            root.host.railExpanded = true;
        search.forceActiveFocus();
    }

    Text {
        id: title
        x: root.pad + 6
        y: 18
        text: I18n.tr("Settings")
        color: root.theme.islandFg
        font.family: root.theme.fontFamily
        font.pixelSize: 28
        font.weight: Font.Bold
        opacity: root.rail ? 0 : 1
        Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
    }

    // Search field (a magnifier button in the rail).
    Rectangle {
        id: field
        x: root.pad
        y: title.y + title.height + 12
        width: root.width - 2 * root.pad
        height: 36
        radius: 10
        color: root.theme.settingsGroup

        Text {
            id: glass
            x: root.rail ? (field.width - width) / 2 : 10
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            color: root.theme.settingsSecondary
            font.family: root.theme.iconFamily
            font.pixelSize: 17
        }

        TextInput {
            id: search
            x: glass.x + glass.width + 8
            width: parent.width - x - 30
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.rail
            clip: true
            color: root.theme.islandFg
            selectionColor: root.theme.qsBlue
            selectByMouse: true
            font.family: root.theme.fontFamily
            font.pixelSize: 15
            onTextEdited: root.host.query = text
            // Esc leaves the field (the query stays; Esc again clears it).
            Keys.onEscapePressed: event => {
                focus = false;
                event.accepted = true;
            }
            // The query is also cleared from outside (Esc, picking a section).
            Connections {
                target: root.host
                function onQueryChanged() {
                    if (search.text !== root.host.query)
                        search.text = root.host.query;
                }
            }

            Text {
                visible: search.text === ""
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Search")
                color: root.theme.settingsSecondary
                font.family: root.theme.fontFamily
                font.pixelSize: 15
            }
        }

        Text {
            visible: !root.rail && root.host.query !== ""
            anchors.right: parent.right
            anchors.rightMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            color: root.theme.settingsSecondary
            font.family: root.theme.iconFamily
            font.pixelSize: 17
            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: root.host.query = ""
            }
        }

        MouseArea {
            anchors.fill: parent
            visible: root.rail
            cursorShape: Qt.PointingHandCursor
            onClicked: root.focusSearch()
        }
    }

    Flickable {
        id: list
        x: root.pad
        y: field.y + field.height + 14
        width: root.width - 2 * root.pad
        height: configButton.y - y - 8
        contentHeight: clusters.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        // The current section's row scrolls into view (a section opened by
        // IPC / Ctrl+PgDn below the fold), springing, with a row of margin.
        readonly property real currentY: root.rowY(root.host.section)
        function reveal(): void {
            if (list.currentY < 0)
                return;
            const margin = root.rowHeight / 2;
            const max = Math.max(0, list.contentHeight - list.height);
            const to = Math.max(0, Math.min(max, Math.min(list.currentY - margin,
                Math.max(list.contentY, list.currentY + root.rowHeight + margin - list.height))));
            if (Math.abs(to - list.contentY) > 0.5) {
                scroll.to = to;
                scroll.restart();
            }
        }
        onCurrentYChanged: list.reveal()
        onHeightChanged: list.reveal()
        Component.onCompleted: Qt.callLater(list.reveal)

        Spring {
            id: scroll
            target: list
            property: "contentY"
            stiffness: 5
            damp: 0.7
            eps: 0.5
        }

        // The current section's accent plate: one plate that springs from
        // row to row (fades while searching); a square around the tile in
        // the rail.
        Rectangle {
            readonly property real tileWidth: 30 + 14
            readonly property real targetY: root.rowY(root.host.section)
            x: root.rail ? (list.width - width) / 2 : 0
            y: Math.max(0, targetY)
            width: root.rail ? tileWidth : list.width
            height: root.rowHeight
            radius: 11
            color: root.theme.qsBlue
            opacity: !root.host.searching && targetY >= 0 ? 1 : 0
            Behavior on y { Spring { stiffness: 6; damp: 0.6; eps: 0.25 } }
            Behavior on width { Spring { stiffness: 6; damp: 0.6 } }
            Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
        }

        // Cluster divider: a full-width rule in the gap (the rows' hairlines
        // are inset past the tiles, this one spans the tiles too); in the
        // rail a short rule under the tiles.
        Repeater {
            model: Schema.SIDEBAR.length - 1

            Rectangle {
                required property int index
                readonly property var next: Schema.SIDEBAR[index + 1][0]
                x: (list.width - width) / 2
                y: Math.round(root.rowY(next.id) - root.clusterGap / 2)
                width: root.rail ? 30 : list.width - 14
                height: 1
                color: root.theme.settingsSeparator
                Behavior on width { Spring { stiffness: 6; damp: 0.6 } }
            }
        }

        Column {
            id: clusters
            width: list.width
            spacing: root.clusterGap

            Repeater {
                model: Schema.SIDEBAR

                Column {
                    id: cluster
                    required property var modelData
                    width: clusters.width
                    spacing: root.rowGap

                    Repeater {
                        model: cluster.modelData

                        SettingsNavRow {
                            required property var modelData
                            required property int index
                            width: clusters.width
                            // Hairline under every row of the cluster but the
                            // last; not next to the accent plate.
                            separator: index < cluster.modelData.length - 1 && !current
                                && !(!root.host.searching && cluster.modelData[index + 1].id === root.host.section)
                            height: root.rowHeight
                            theme: root.theme
                            section: modelData
                            rail: root.rail
                            current: !root.host.searching && root.host.section === modelData.id
                            onPicked: root.host.showSection(modelData.id)
                        }
                    }
                }
            }
        }
    }

    // Config file (end-4): click = open, right click = copy the path.
    Rectangle {
        id: configButton
        property bool copied: false
        x: root.pad
        y: root.height - height - root.pad
        width: root.width - 2 * root.pad
        height: 40
        radius: 11
        color: configArea.containsMouse ? root.theme.settingsGroup : "transparent"

        Text {
            id: configGlyph
            x: root.rail ? (configButton.width - width) / 2 : 12
            anchors.verticalCenter: parent.verticalCenter
            text: configButton.copied ? "" : ""
            color: root.theme.settingsSecondary
            font.family: root.theme.iconFamily
            font.pixelSize: 19
        }
        Text {
            x: configGlyph.x + configGlyph.width + 10
            anchors.verticalCenter: parent.verticalCenter
            text: configButton.copied ? I18n.tr("Path copied") : I18n.tr("Config file")
            color: root.theme.settingsSecondary
            font.family: root.theme.fontFamily
            font.pixelSize: 14
            opacity: root.rail ? 0 : 1
            Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
        }

        Timer {
            id: copiedReset
            interval: 1500
            onTriggered: configButton.copied = false
        }

        MouseArea {
            id: configArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    Quickshell.clipboardText = root.configPath;
                    configButton.copied = true;
                    copiedReset.restart();
                } else {
                    Qt.openUrlExternally(`file://${root.configPath}`);
                }
            }
        }
    }
}
