import QtQuick
import QtQuick.Shapes
import "../../../components"

// Battery card (2x1, iOS Batteries widget): level ring with a device glyph
// (laptop, or a bolt while charging) on the left; big percentage + state
// on the right.
DashboardCard {
    id: root
    required property var battery

    readonly property int spanCols: 2
    readonly property int spanRows: 1

    readonly property real _pad: (dash?.cardPadding) ?? 10
    readonly property real _ringBox: root.height - 2 * _pad
    readonly property real _ringW: Math.max(4, Math.round(_ringBox / 11))

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
        return h > 0 ? `${h} ч ${m} мин` : `${m} мин`;
    }

    readonly property string statusStr: {
        if (!root.present)
            return "Нет батареи";
        if (root.charging) {
            const full = root.fmtDur(battery?.secondsToFull ?? 0);
            return root.pct >= 100 ? "Заряжена" : (full ? `до полной ${full}` : "Заряжается");
        }
        const left = root.fmtDur(battery?.secondsToEmpty ?? 0);
        return left ? `осталось ${left}` : "Батарея";
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
                    radius: 2
                    color: "transparent"
                    border.color: "white"
                    border.width: 2
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 2.5
                    radius: 1.25
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
                    strokeWidth: 1.5
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
            anchors.leftMargin: 12
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
