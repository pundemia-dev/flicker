import QtQuick
import Quickshell
import Quickshell.Io
import "../../components"

// Dashboard (spec: widget set TBD) — a minimal, working set: clock, date and
// live system load / memory. Opened from the clock drag gesture.
Item {
    id: root
    signal closeRequested

    property string load: "--"
    property string mem: "--"

    Process {
        id: statsProc
        command: ["sh", "-c", "cat /proc/loadavg; free -m | awk '/Mem:/{print $3, $2}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                root.load = (lines[0] ?? "").split(" ")[0] ?? "--";
                const m = (lines[1] ?? "").split(" ");
                if (m.length === 2)
                    root.mem = `${m[0]} / ${m[1]} MB`;
            }
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: statsProc.running = true
    }

    Column {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 6

        Text {
            text: Qt.formatDateTime(new Date(), "HH:mm")
            color: "#F3F6FC"
            font.pixelSize: 40
            font.weight: Font.Light
        }
        Text {
            text: Qt.formatDateTime(new Date(), "dddd, d MMMM")
            color: "#98A4B6"
            font.pixelSize: 12
        }

        Row {
            spacing: 24
            anchors.topMargin: 4

            Column {
                spacing: 2
                Text { text: "Load"; color: "#7C879A"; font.pixelSize: 10 }
                Text { text: root.load; color: "#E3E9F4"; font.pixelSize: 13 }
            }
            Column {
                spacing: 2
                Text { text: "Memory"; color: "#7C879A"; font.pixelSize: 10 }
                Text { text: root.mem; color: "#E3E9F4"; font.pixelSize: 13 }
            }
        }
    }
}
