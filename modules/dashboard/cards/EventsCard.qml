import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../../../config"

// Agenda card. No calendar backend is wired yet, so `events` stays empty and
// the card renders its empty state — the list model + delegate already match
// the intended shape ({ time, title }) for a future source to fill in.
DashboardCard {
    id: root

    // Future source: [{ time: "10:30", title: "..." }].
    property var events: []

    // Grid-first: show as many 18px rows as fit the allocated height.
    readonly property real _innerH: root.height - 2 * ((root.dash?.cardPadding) ?? 10)
    readonly property int _maxRows: Math.max(1, Math.floor((_innerH - ((root.dash?.titleSize) ?? 13) * 1.3) / 21))

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.dash?.cardPadding ?? 10
        spacing: 3

        CardTitle {
            label: I18n.tr("Events")
            theme: root.theme
            dash: root.dash
        }

        Text {
            visible: root.events.length === 0
            text: I18n.tr("No events")
            color: root.theme?.cardDim ?? "#99EBEBF5"
            font.pixelSize: root.dash?.titleSize ?? 13
        }

        Repeater {
            model: root.events.slice(0, root._maxRows)
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 18
                spacing: 10

                Text {
                    text: modelData.time ?? ""
                    color: root.theme?.cardDim ?? "#99EBEBF5"
                    font.pixelSize: root.dash?.titleSize ?? 13
                    font.weight: Font.DemiBold
                    Layout.preferredWidth: 36
                }
                Text {
                    text: modelData.title ?? ""
                    color: "white"
                    font.pixelSize: (root.dash?.titleSize ?? 13) + 1
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }
    }
}
