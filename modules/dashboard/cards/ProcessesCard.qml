import QtQuick
import QtQuick.Layouts
import "../../../components"

// Top CPU consumers from the SystemUsage service, each with a load-colored
// mini bar. Shows a gathering-data placeholder until the first ps sample.
DashboardCard {
    id: root
    required property var systemUsage

    // Grid footprint in units, hardcoded here (grid-first).
    readonly property int spanCols: 4
    readonly property int spanRows: 1

    readonly property var rows: (systemUsage?.topProcesses) ?? []

    // Grid-first: show as many 18px rows as fit the allocated height.
    readonly property real _innerH: root.height - 2 * ((root.dash?.cardPadding) ?? 10)
    readonly property int _maxRows: Math.max(1, Math.floor((_innerH - ((root.dash?.titleSize) ?? 13) * 1.3) / 21))

    function barColor(cpu: real): color {
        if (cpu >= 20)
            return root.theme?.accentRed ?? "#E4483E";
        if (cpu >= 10)
            return root.theme?.accentOrange ?? "#E58B4D";
        return root.theme?.accentGreen ?? "#3DBD4E";
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.dash?.cardPadding ?? 10
        spacing: 3

        CardTitle {
            label: "Активные процессы"
            theme: root.theme
            dash: root.dash
        }

        Text {
            visible: root.rows.length === 0
            text: "Сбор данных…"
            color: root.theme?.cardDim ?? "#99EBEBF5"
            font.pixelSize: root.dash?.titleSize ?? 13
        }

        Repeater {
            model: root.rows.slice(0, root._maxRows)
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 18
                spacing: 10

                Text {
                    text: modelData.name ?? ""
                    color: "white"
                    font.pixelSize: root.dash?.titleSize ?? 13
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                MiniBar {
                    theme: root.theme
                    Layout.preferredWidth: 48
                    Layout.alignment: Qt.AlignVCenter
                    value: (modelData.cpu ?? 0) / 100
                    fill: root.barColor(modelData.cpu ?? 0)
                }
                Text {
                    text: `${Math.round(modelData.cpu ?? 0)}%`
                    color: root.theme?.cardDim ?? "#99EBEBF5"
                    font.pixelSize: root.dash?.titleSize ?? 13
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignRight
                    Layout.preferredWidth: 28
                }
            }
        }
    }
}
