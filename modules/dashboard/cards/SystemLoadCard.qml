import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../../../config"

// CPU / RAM / disk as three concentric rings + legend. Layout: fixed title
// row pinned top-left, bottom row = square indicator box (left, as large as
// fits) + legend column taking the remaining width with auto-scaled fonts.
// Stock 2x2; sizes in DashCatalog.js.
DashboardCard {
    id: root
    required property var systemUsage

    readonly property real cpuFrac: (systemUsage?.cpuPerc) ?? 0
    readonly property real memFrac: (systemUsage?.memPerc) ?? 0
    readonly property real diskFrac: (systemUsage?.storagePerc) ?? 0

    // Stable inputs: card size comes from the grid (never from our content),
    // title estimate from config font metrics. The box takes the smaller of
    // the height and width budgets, so it stays square in portrait cards too;
    // the legend keeps its target width, which keeps its text size fixed —
    // shrinking the card scales the rings, never the text.
    readonly property real _pad: (dash?.cardPadding) ?? 10
    readonly property real _titleEst: Math.ceil(((dash?.titleSize) ?? 13) * 1.4)
    readonly property real _colGap: 8
    readonly property real _rowGap: 15
    readonly property real _legendTarget: 40
    readonly property real _innerH: root.height - 2 * _pad
    readonly property real _innerW: root.width - 2 * _pad
    readonly property real _boxSide: Math.max(50, Math.min(_innerH - _titleEst - _colGap, _innerW - _legendTarget - _rowGap))
    readonly property real _legendW: Math.max(20, _innerW - _boxSide - _rowGap)
    readonly property real _ringW: Math.max(8, Math.round(_boxSide / 12))
    readonly property real _ringStep: _ringW + 5
    readonly property real _ringOuter: _boxSide / 2 - _ringW / 2 - 2.5
    readonly property real _valueFs: Math.max(10, Math.min(20, _legendW * 0.42))
    readonly property real _labelFs: Math.max(9, Math.round(_valueFs * 0.75))

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root._pad
        spacing: root._colGap

        RowLayout {
            spacing: 10

            Rectangle {
                id: dot
                Layout.preferredWidth: (root.dash?.dotSize) ?? 8
                Layout.preferredHeight: (root.dash?.dotSize) ?? 8
                Layout.alignment: Qt.AlignVCenter
                radius: width / 2
                color: root.theme?.accentRed ?? "#E4483E"
            }

            CardTitle {
                Layout.fillWidth: true
                label: I18n.tr("Load")
                theme: root.theme
                dash: root.dash
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: root._rowGap

            Item {
                Layout.preferredWidth: root._boxSide
                Layout.preferredHeight: root._boxSide
                Layout.alignment: Qt.AlignVCenter

                RingArc {
                    anchors.fill: parent
                    ringRadius: root._ringOuter
                    ringWidth: root._ringW
                    ringColor: root.theme?.accentRed ?? "#E4483E"
                    trackColor: root.theme?.cardTrack ?? "#2C2C2E"
                    value: root.cpuFrac
                }
                RingArc {
                    anchors.fill: parent
                    ringRadius: root._ringOuter - root._ringStep
                    ringWidth: root._ringW
                    ringColor: root.theme?.accentGreen ?? "#3DBD4E"
                    trackColor: root.theme?.cardTrack ?? "#2C2C2E"
                    value: root.memFrac
                }
                RingArc {
                    anchors.fill: parent
                    ringRadius: root._ringOuter - 2 * root._ringStep
                    ringWidth: root._ringW
                    ringColor: root.theme?.cardBlue ?? "#0F7CEC"
                    trackColor: root.theme?.cardTrack ?? "#2C2C2E"
                    value: root.diskFrac
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 6

                Metric {
                    value: Math.round(root.cpuFrac * 100)
                    unit: "CPU"
                    color: root.theme?.accentRed ?? "#E4483E"
                    theme: root.theme
                    dash: root.dash
                    valueFs: root._valueFs
                    labelFs: root._labelFs
                }
                Metric {
                    value: Math.round(root.memFrac * 100)
                    unit: "RAM"
                    color: root.theme?.accentGreen ?? "#3DBD4E"
                    theme: root.theme
                    dash: root.dash
                    valueFs: root._valueFs
                    labelFs: root._labelFs
                }
                Metric {
                    value: Math.round(root.diskFrac * 100)
                    unit: I18n.tr("Disk")
                    color: root.theme?.cardBlue ?? "#0F7CEC"
                    theme: root.theme
                    dash: root.dash
                    valueFs: root._valueFs
                    labelFs: root._labelFs
                }
            }
        }
    }

    component Metric: ColumnLayout {
        id: metric
        property int value: 0
        property string unit: ""
        property color color: "white"
        property var theme: null
        property var dash: null
        property real valueFs: 24
        property real labelFs: 13

        spacing: 0

        // Changed digits roll (up on increase, down on decrease).
        RollingText {
            text: `${metric.value}%`
            color: metric.color
            pixelSize: metric.valueFs
            weight: Font.DemiBold
        }
        Text {
            text: metric.unit
            color: metric.theme?.cardDim ?? "#99EBEBF5"
            font.pixelSize: metric.labelFs
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
    }
}
