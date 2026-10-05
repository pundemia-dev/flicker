import QtQuick
import QtQuick.Shapes
import "../../../components"

// Hardware sensors (2x1, iOS stat tile): CPU temperature (heat-coloured)
// left, fan speed right, a faint temperature sparkline along the bottom.
// Heat bands: Config.dashboard.tempWarm / tempHot (°C).
DashboardCard {
    id: root
    required property var sensors

    readonly property int spanCols: 2
    readonly property int spanRows: 1

    readonly property real _pad: (dash?.cardPadding) ?? 10
    readonly property real temp: (sensors?.cpuTemp) ?? NaN
    readonly property bool hasTemp: isFinite(root.temp)
    readonly property var hist: (sensors?.tempHistory) ?? []

    readonly property color heat: {
        if (!root.hasTemp)
            return root.theme?.cardDim ?? "#99EBEBF5";
        if (root.temp >= ((root.dash?.tempHot) ?? 80))
            return root.theme?.accentRed ?? "#E4483E";
        if (root.temp >= ((root.dash?.tempWarm) ?? 60))
            return root.theme?.accentOrange ?? "#E58B4D";
        return root.theme?.accentGreen ?? "#3DBD4E";
    }

    // Sparkline: last samples scaled to their own min..max (+-2°C floor so
    // a flat line stays flat instead of amplifying noise).
    Shape {
        id: spark
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: root._pad
        anchors.rightMargin: root._pad
        anchors.bottomMargin: root._pad - 2.5
        height: 20
        visible: root.hist.length > 1
        opacity: 0.55
        preferredRendererType: Shape.CurveRenderer

        readonly property real lo: Math.min(...root.hist) - 2
        readonly property real hi: Math.max(...root.hist) + 2

        ShapePath {
            strokeColor: root.heat
            strokeWidth: 2
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline {
                path: root.hist.map((t, i) => Qt.point(
                    i / Math.max(1, root.hist.length - 1) * spark.width,
                    spark.height - (t - spark.lo) / Math.max(1, spark.hi - spark.lo) * spark.height))
            }
        }
    }

    Item {
        anchors.fill: parent
        anchors.margins: root._pad
        anchors.bottomMargin: root._pad + spark.height - 2.5

        Column {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: -2.5

            // Changed digits roll (up on increase, down on decrease).
            RollingText {
                text: root.hasTemp ? `${Math.round(root.temp)}°` : "—"
                color: root.heat
                pixelSize: 28
                weight: Font.DemiBold
            }
            Text {
                text: "CPU"
                color: root.theme?.cardDim ?? "#99EBEBF5"
                font.pixelSize: (root.dash?.titleSize ?? 13) - 2
            }
        }
        Column {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: -2.5
            visible: (root.sensors?.hasFans) ?? false

            RollingText {
                anchors.right: parent.right
                text: String(Math.round(((root.sensors?.fanRpm) ?? 0) / 10) * 10)
                color: "white"
                pixelSize: 28
                weight: Font.DemiBold
            }
            Text {
                anchors.right: parent.right
                text: "об/мин"
                color: root.theme?.cardDim ?? "#99EBEBF5"
                font.pixelSize: (root.dash?.titleSize ?? 13) - 2
            }
        }
    }
}
