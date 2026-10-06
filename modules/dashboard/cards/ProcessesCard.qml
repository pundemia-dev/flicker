import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../../../config"

// Top CPU consumers (4x1, iOS stat tiles): three equal columns, each with
// the load as a big load-coloured number, the process name and a mini bar,
// separated by hairlines. Placeholder until the first ps sample.
DashboardCard {
    id: root
    required property var systemUsage

    // Grid footprint in units, hardcoded here (grid-first).
    readonly property int spanCols: 4
    readonly property int spanRows: 1

    readonly property int _slots: 3
    readonly property var rows: ((systemUsage?.topProcesses) ?? []).slice(0, _slots)

    function loadColor(cpu: real): color {
        if (cpu >= 20)
            return root.theme?.accentRed ?? "#E4483E";
        if (cpu >= 10)
            return root.theme?.accentOrange ?? "#E58B4D";
        return root.theme?.accentGreen ?? "#3DBD4E";
    }

    Text {
        anchors.centerIn: parent
        visible: root.rows.length === 0
        text: I18n.tr("Collecting data…")
        color: root.theme?.cardDim ?? "#99EBEBF5"
        font.pixelSize: root.dash?.titleSize ?? 13
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: root.dash?.cardPadding ?? 10
        spacing: 0
        visible: root.rows.length > 0

        Repeater {
            model: root._slots
            delegate: RowLayout {
                id: slot
                required property int index
                readonly property var proc: root.rows[slot.index] ?? null
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                spacing: 0

                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    Layout.topMargin: 8
                    Layout.bottomMargin: 8
                    color: root.theme?.cardTrack ?? "#2C2C2E"
                    visible: slot.index > 0
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    Layout.leftMargin: slot.index > 0 ? 12 : 0
                    Layout.rightMargin: slot.index < root._slots - 1 ? 12 : 0
                    spacing: 1
                    opacity: slot.proc ? 1 : 0

                    // Changed digits roll (up on increase, down on decrease).
                    RollingText {
                        text: `${Math.round(slot.proc?.cpu ?? 0)}%`
                        color: root.loadColor(slot.proc?.cpu ?? 0)
                        pixelSize: 25
                        weight: Font.DemiBold
                    }
                    Text {
                        Layout.fillWidth: true
                        text: slot.proc?.name ?? ""
                        color: root.theme?.cardDim ?? "#99EBEBF5"
                        font.pixelSize: (root.dash?.titleSize ?? 13) - 1
                        elide: Text.ElideRight
                    }
                    MiniBar {
                        theme: root.theme
                        Layout.fillWidth: true
                        Layout.topMargin: 5
                        height: 5
                        radius: height / 2
                        value: (slot.proc?.cpu ?? 0) / 100
                        fill: root.loadColor(slot.proc?.cpu ?? 0)
                    }
                }
            }
        }
    }
}
