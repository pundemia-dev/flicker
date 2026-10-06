import QtQuick
import "../../components"
import "QsCatalog.js" as QsCatalog
import "../../config"

// Edit-mode footer: hidden cards as glyph chips (tap = add back at the
// first free slot) + "Готово" (saves, leaves edit mode). Row count is
// mirrored by QsMetrics.footerHeight.
Item {
    id: root
    required property var cfg
    required property var theme
    property var frost: null
    required property var hiddenIds
    signal addRequested(string id)
    signal doneRequested

    Flow {
        id: chips
        width: root.width - root.cfg.doneWidth - root.cfg.spacing
        spacing: root.cfg.chipSpacing

        Repeater {
            model: root.hiddenIds
            delegate: Rectangle {
                id: chip
                required property string modelData
                width: root.cfg.chipSize
                height: width
                radius: width / 2
                readonly property color base: ma.containsMouse ? (root.theme?.qsDisc ?? "#3A3A3C") : (root.theme?.cardBg ?? "#1C1C1E")
                color: root.frost?.layerColor(chip.base) ?? chip.base

                Icon {
                    anchors.centerIn: parent
                    text: QsCatalog.glyphOf(chip.modelData)
                    font.family: root.theme?.iconFamily ?? "tabler-icons"
                    iconSize: Math.round(chip.width * 0.5)
                    iconColor: "white"
                }
                // "+" corner mark: this chip adds, it is not a toggle.
                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: -2
                    width: 14
                    height: 14
                    radius: 7
                    color: root.theme?.qsBlue ?? "#0A84FF"
                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        color: "white"
                    }
                }
                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.addRequested(chip.modelData)
                }
            }
        }
    }

    // Hint when nothing is hidden.
    Text {
        anchors.verticalCenter: done.verticalCenter
        visible: root.hiddenIds.length === 0
        text: I18n.tr("All items are in place")
        color: root.theme?.cardDim ?? "#99EBEBF5"
        font.pixelSize: (root.cfg?.subtitleSize) ?? 11
    }

    Rectangle {
        id: done
        anchors.right: parent.right
        anchors.top: parent.top
        width: root.cfg.doneWidth
        height: root.cfg.chipSize
        radius: height / 2
        color: doneMa.pressed ? Qt.darker(root.theme?.qsBlue ?? "#0A84FF", 1.2) : (root.theme?.qsBlue ?? "#0A84FF")

        Text {
            anchors.centerIn: parent
            text: I18n.tr("Done")
            color: "white"
            font.pixelSize: (root.cfg?.titleSize) ?? 13
            font.weight: Font.DemiBold
        }
        MouseArea {
            id: doneMa
            anchors.fill: parent
            onClicked: root.doneRequested()
        }
    }
}
