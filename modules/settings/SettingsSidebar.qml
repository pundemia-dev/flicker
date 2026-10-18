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
    readonly property string configPath: `${Quickshell.shellDir}/config/config.json`

    width: root.rail ? root.railWidth : root.fullWidth
    Behavior on width { Spring { stiffness: 6; damp: 0.65 } }
    color: root.theme.settingsBg
    clip: true

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

        Column {
            id: clusters
            width: list.width
            spacing: 16

            Repeater {
                model: Schema.SIDEBAR

                Column {
                    required property var modelData
                    width: clusters.width
                    spacing: 2

                    Repeater {
                        model: modelData

                        SettingsNavRow {
                            required property var modelData
                            width: clusters.width
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
