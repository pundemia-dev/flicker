import QtQuick
import QtQuick.Layouts
import "../../../components"

// Battery level + bar + remaining/charging state from the Battery service.
DashboardCard {
    id: root
    required property var battery

    readonly property int spanCols: 4
    readonly property int spanRows: 1

    // Grid-first: the percentage scales to the allocated height
    // (title + bar + subtitle + gaps eat ~48px), clamped to the theme size.
    readonly property real _innerH: root.height - 2 * ((root.dash?.cardPadding) ?? 10)
    readonly property real _valFs: Math.max(12, Math.min((root.dash?.valueSize) ?? 24, (_innerH - 48) * 0.84))

    readonly property bool present: (battery?.present) ?? false
    readonly property bool charging: (battery?.charging) ?? false
    readonly property int pct: (battery?.percent) ?? 0

    readonly property color barColor: {
        if (!root.present)
            return root.theme?.cardTrack ?? "#2C2C2E";
        if (root.charging)
            return root.theme?.batteryGood ?? "#59D67A";
        if ((battery?.low) ?? false)
            return root.theme?.batteryLow ?? "#E35D5D";
        return root.theme?.batteryGood ?? "#59D67A";
    }

    function fmtDur(sec: int): string {
        if (!(sec > 0))
            return "—";
        const h = Math.floor(sec / 3600);
        const m = Math.floor((sec % 3600) / 60);
        return h > 0 ? `${h} ч ${m} мин` : `${m} мин`;
    }

    readonly property string statusStr: {
        if (!root.present)
            return "Батарея не найдена";
        if (root.charging)
            return "Заряжается";
        const left = root.fmtDur(battery?.secondsToEmpty ?? 0);
        return ((battery?.low) ?? false) ? `Низкий заряд · осталось ${left}` : `Осталось ${left}`;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.dash?.cardPadding ?? 10
        spacing: 2

        CardTitle {
            label: "Батарея"
            theme: root.theme
            dash: root.dash
        }
        Item { Layout.fillHeight: true }
        Text {
            text: root.present ? `${root.pct}%` : "—"
            color: "white"
            font.pixelSize: root._valFs
            font.weight: Font.DemiBold
        }
        MiniBar {
            theme: root.theme
            Layout.fillWidth: true
            value: root.present ? root.pct / 100 : 0
            fill: root.barColor
        }
        Text {
            text: root.statusStr
            color: root.theme?.cardDim ?? "#99EBEBF5"
            font.pixelSize: root.dash?.titleSize ?? 13
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
    }
}
