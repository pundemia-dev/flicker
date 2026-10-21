import QtQuick
import QtQuick.Shapes
import "../../../components"
import "../../../config"

// Battery card (2x1, iOS Batteries widget): level ring with a device glyph
// (laptop, or a bolt while charging) on the left; big percentage + state
// on the right.
DashboardCard {
    id: root
    required property var battery

    readonly property real _pad: (dash?.cardPadding) ?? 10
    readonly property real _ringBox: root.height - 2 * _pad
    readonly property real _ringW: Math.max(5, Math.round(_ringBox / 11))

    readonly property bool present: (battery?.present) ?? false
    readonly property bool charging: (battery?.charging) ?? false
    readonly property bool low: (battery?.low) ?? false
    readonly property int pct: (battery?.percent) ?? 0

    readonly property color levelColor: {
        if (root.low)
            return root.theme?.batteryLow ?? "#E35D5D";
        return root.theme?.batteryGood ?? "#59D67A";
    }

    function fmtDur(sec: int): string {
        if (!(sec > 0))
            return "";
        const h = Math.floor(sec / 3600);
        const m = Math.floor((sec % 3600) / 60);
        return h > 0 ? I18n.tr("%1 h %2 min").arg(h).arg(m) : I18n.tr("%1 min").arg(m);
    }

    readonly property string statusStr: {
        if (!root.present)
            return I18n.tr("No battery");
        if (root.charging) {
            const full = root.fmtDur(battery?.secondsToFull ?? 0);
            return root.pct >= 100 ? I18n.tr("Charged") : (full ? I18n.tr("%1 until full").arg(full) : I18n.tr("Charging"));
        }
        const left = root.fmtDur(battery?.secondsToEmpty ?? 0);
        return left ? I18n.tr("%1 left").arg(left) : I18n.tr("Battery");
    }

    Item {
        anchors.fill: parent
        anchors.margins: root._pad

        Item {
            id: ring
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: root._ringBox
            height: root._ringBox

            RingArc {
                anchors.fill: parent
                ringRadius: root._ringBox / 2 - root._ringW / 2
                ringWidth: root._ringW
                ringColor: root.levelColor
                trackColor: root.theme?.cardTrack ?? "#2C2C2E"
                value: root.present ? root.pct / 100 : 0
            }

            // Laptop: screen outline + base.
            Item {
                anchors.centerIn: parent
                width: root._ringBox * 0.38
                height: width * 0.72
                visible: !root.charging

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    width: parent.width * 0.78
                    height: parent.height * 0.78
                    radius: 2.5
                    color: "transparent"
                    border.color: "white"
                    border.width: 3
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 3
                    radius: height / 2
                    color: "white"
                }
            }

            // Charging bolt.
            Shape {
                anchors.centerIn: parent
                width: root._ringBox * 0.24
                height: width * 1.5
                visible: root.charging
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    id: bolt
                    readonly property real w: root._ringBox * 0.24
                    readonly property real h: bolt.w * 1.5
                    fillColor: root.levelColor
                    strokeColor: root.levelColor
                    strokeWidth: 2
                    joinStyle: ShapePath.RoundJoin
                    PathMove { x: bolt.w * 0.62; y: 0 }
                    PathLine { x: 0; y: bolt.h * 0.56 }
                    PathLine { x: bolt.w * 0.46; y: bolt.h * 0.56 }
                    PathLine { x: bolt.w * 0.38; y: bolt.h }
                    PathLine { x: bolt.w; y: bolt.h * 0.42 }
                    PathLine { x: bolt.w * 0.54; y: bolt.h * 0.42 }
                    PathLine { x: bolt.w * 0.62; y: 0 }
                }
            }
        }

        Column {
            anchors.left: ring.right
            anchors.leftMargin: 15
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            // Changed digits roll (up on increase, down on decrease).
            RollingText {
                text: root.present ? `${root.pct}%` : "—"
                color: "white"
                pixelSize: root.dash?.valueSize ?? 24
                weight: Font.DemiBold
            }
            Text {
                width: parent.width
                text: root.statusStr
                color: root.theme?.cardDim ?? "#99EBEBF5"
                font.pixelSize: (root.dash?.titleSize ?? 13) - 1
                elide: Text.ElideRight
            }
        }
    }
}
