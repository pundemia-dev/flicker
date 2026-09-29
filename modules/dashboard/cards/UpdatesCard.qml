import QtQuick
import Quickshell.Io
import QtQuick.Layouts
import "../../../components"

// Pending pacman + AUR updates (checkupdates / yay-or-paru) and days since
// the last -Syu (from /var/log/pacman.log mtime). Missing tools degrade to
// the unknown state, never to fake zeroes.
DashboardCard {
    id: root

    readonly property int spanCols: 2
    readonly property int spanRows: 1

    // Grid-first: the headline scales to the allocated height
    // (title + subtitle + gaps eat ~40px), clamped to the theme size.
    readonly property real _innerH: root.height - 2 * ((root.dash?.cardPadding) ?? 10)
    readonly property real _bigFs: Math.max(14, Math.min((root.dash?.valueSize) ?? 24, (_innerH - 40) * 0.84))

    property int repoCount: -1
    property int aurCount: -1
    property real lastSyncEpoch: 0

    readonly property int total: (root.repoCount < 0 || root.aurCount < 0) ? -1 : root.repoCount + root.aurCount

    function plural(n: int): string {
        const m10 = n % 10, m100 = n % 100;
        if (m10 === 1 && m100 !== 11)
            return "пакет";
        if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14))
            return "пакета";
        return "пакетов";
    }

    function dayPlural(n: int): string {
        const m10 = n % 10, m100 = n % 100;
        if (m10 === 1 && m100 !== 11)
            return "день";
        if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14))
            return "дня";
        return "дней";
    }

    readonly property string bigStr: {
        if (root.total < 0)
            return "—";
        if (root.total === 0)
            return "Всё обновлено";
        return `${root.total} ${root.plural(root.total)}`;
    }

    readonly property string subStr: {
        if (!(root.lastSyncEpoch > 0))
            return "pacman.log недоступен";
        const days = Math.floor((Date.now() / 1000 - root.lastSyncEpoch) / 86400);
        if (days <= 0)
            return "Обновлено сегодня";
        return `-Syu ${days} ${root.dayPlural(days)} назад`;
    }

    Timer {
        interval: (root.dash?.updatesPollMs) ?? 900000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: updatesProc.running = true
    }

    Process {
        id: updatesProc
        command: ["sh", "-c", "checkupdates 2>/dev/null | wc -l; { yay -Qua 2>/dev/null || paru -Qua 2>/dev/null; } | wc -l; stat -c %Y /var/log/pacman.log 2>/dev/null || echo 0"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                const repo = parseInt(lines[0] ?? "-1");
                const aur = parseInt(lines[1] ?? "-1");
                root.repoCount = isNaN(repo) ? -1 : repo;
                root.aurCount = isNaN(aur) ? -1 : aur;
                root.lastSyncEpoch = parseFloat(lines[2] ?? "0") || 0;
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.dash?.cardPadding ?? 10
        spacing: 2

        CardTitle {
            label: "Обновления"
            theme: root.theme
            dash: root.dash
        }
        Item { Layout.fillHeight: true }
        Text {
            text: root.bigStr
            color: "white"
            font.pixelSize: root._bigFs
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        Text {
            text: root.subStr
            color: root.theme?.cardDim ?? "#99EBEBF5"
            font.pixelSize: root.dash?.titleSize ?? 13
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
    }
}
