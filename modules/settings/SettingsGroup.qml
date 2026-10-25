import QtQuick
import "../../components"
import "../../config"

// iOS inset grouped section: small grey header, the rows in one rounded
// card (hairlines between rows, inset past the label start), grey footer.
// A search result group carries `section`: its header links to the section.
Column {
    id: root
    required property var host
    required property var theme
    required property var group
    spacing: 7

    Item {
        visible: !!root.group.title
        width: parent.width
        height: header.implicitHeight

        Text {
            id: header
            x: 16
            text: I18n.tr(root.group.title ?? "").toUpperCase()
            color: root.theme.settingsSecondary
            font.family: root.theme.fontFamily
            font.pixelSize: 12
            font.letterSpacing: 0.3
        }

        Row {
            id: open
            visible: !!root.group.section
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Open")
                color: root.theme.qsBlue
                font.family: root.theme.fontFamily
                font.pixelSize: 12
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\uea61"
                color: root.theme.qsBlue
                font.family: root.theme.iconFamily
                font.pixelSize: 13
            }
        }
        MouseArea {
            visible: open.visible
            x: open.x - 6
            width: open.width + 12
            height: parent.height
            cursorShape: Qt.PointingHandCursor
            onClicked: root.host.showSection(root.group.section)
        }
    }

    Rectangle {
        width: parent.width
        height: rows.height
        radius: 12
        color: root.theme.settingsGroup

        Column {
            id: rows
            width: parent.width

            // A group's `widget`: a custom control above its rows.
            Loader {
                active: root.group.widget === "displays"
                visible: active
                width: rows.width
                sourceComponent: SettingsDisplaysArrangement {
                    host: root.host
                    theme: root.theme
                }
            }

            Repeater {
                model: root.group.rows

                SettingsRow {
                    required property var modelData
                    required property int index
                    width: rows.width
                    host: root.host
                    theme: root.theme
                    row: modelData
                    separator: index < root.group.rows.length - 1
                    first: index === 0
                    last: index === root.group.rows.length - 1
                }
            }
        }
    }

    // Live footer (`footerFrom`): an error replaces it, in red.
    readonly property var footer: root.group.footerFrom ? root.host.footerOf(root.group)
        : ({ text: I18n.tr(root.group.footer ?? ""), alert: false })

    Text {
        visible: root.footer.text !== ""
        x: 16
        width: parent.width - 32
        text: root.footer.text
        wrapMode: Text.Wrap
        color: root.footer.alert ? root.theme.accentRed : root.theme.settingsSecondary
        font.family: root.theme.fontFamily
        font.pixelSize: 12
        lineHeight: 1.15
    }
}
