import QtQuick
import "../../../components"

// The calculator's result row (Raycast-style): the expression on the left,
// an arrow, the answer large on the right, each with a caption (what it is:
// "US dollar", "Length", "= 1/3", the rates date). `slot` is the live
// Calculator.CalcSlot: its text changes in place while typing. A stale
// answer (the expression is mid-edit) dims; an error takes the answer's
// place in the dim caption colour.
Item {
    id: root
    required property var slot
    required property var theme
    required property var cfg

    readonly property real gap: root.cfg.itemPadding
    readonly property real arrowBox: root.cfg.iconBox * 0.8

    // Placeholder (forced mode, nothing typed yet): one centred hint.
    Column {
        anchors.centerIn: parent
        width: parent.width
        visible: root.slot.placeholder
        spacing: 2

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.slot.header
            font.pixelSize: root.cfg.fontSize * 1.15
            font.weight: Font.DemiBold
            color: root.theme.islandFg
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.slot.text
            font.pixelSize: root.cfg.subFontSize
            color: root.theme.cardDim
            elide: Text.ElideMiddle
        }
    }

    Item {
        anchors.fill: parent
        visible: !root.slot.placeholder

        Column {
            id: left
            anchors.left: parent.left
            anchors.right: arrow.left
            anchors.rightMargin: root.gap
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            Text {
                width: parent.width
                text: root.slot.expr
                font.pixelSize: root.cfg.fontSize * 1.2
                font.features: { "tnum": 1 }
                color: root.theme.subtleFg
                elide: Text.ElideLeft
            }
            Text {
                width: parent.width
                text: root.slot.exprCaption
                font.pixelSize: root.cfg.subFontSize
                color: root.theme.cardDim
                elide: Text.ElideRight
            }
        }

        Rectangle {
            id: arrow
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: -parent.width * 0.08
            anchors.verticalCenter: parent.verticalCenter
            width: root.arrowBox
            height: width
            radius: width / 2
            color: root.theme.qsDisc

            Text {
                anchors.centerIn: parent
                text: "" // tabler arrow-right
                font.family: root.theme.iconFamily
                font.pixelSize: root.cfg.iconSize * 0.85
                color: root.theme.islandFg
            }
        }

        Column {
            anchors.left: arrow.right
            anchors.leftMargin: root.gap
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            opacity: root.slot.stale ? 0.45 : 1
            Behavior on opacity { Spring { eps: 0.01 } }

            Text {
                width: parent.width
                height: root.cfg.fontSize * 2.3
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                text: root.slot.header
                // Long answers shrink to fit instead of eliding digits.
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: root.cfg.subFontSize
                font.pixelSize: root.slot.error ? root.cfg.fontSize : root.cfg.fontSize * 1.85
                font.weight: root.slot.error ? Font.Medium : Font.DemiBold
                font.features: { "tnum": 1 }
                color: root.slot.error ? root.theme.cardDim : root.theme.islandFg
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignRight
                visible: text !== ""
                text: root.slot.text
                font.pixelSize: root.cfg.subFontSize
                color: root.theme.cardDim
                elide: Text.ElideLeft
            }
        }
    }
}
