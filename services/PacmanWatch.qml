import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// pacman / yay / paru transactions (status `pacman`): busy while
// /var/lib/pacman/db.lck exists (polled — no inotify tool here; a [ -e ]
// every `status.pacmanPollMs`). pacman reports no total up front, so the
// drop spins; `count` = packages done so far, counted from the ALPM lines
// /var/log/pacman.log gained since the lock appeared. When the lock goes:
// `finished(count)` → an event "N packages updated" (pacman eating boxes).
Scope {
    id: root
    required property var events

    readonly property var cfg: Config.data.status
    readonly property bool enabled: root.cfg.pacman ?? true
    property bool busy: false
    property int count: 0
    // pacman.log size when the lock appeared (-1 = idle).
    property real logStart: -1

    Timer {
        running: root.enabled
        repeat: true
        triggeredOnStart: true
        interval: root.busy ? (root.cfg.pacmanBusyPollMs ?? 1000) : (root.cfg.pacmanPollMs ?? 2000)
        onTriggered: if (!poll.running) poll.running = true
    }

    Process {
        id: poll
        command: ["sh", "-c", "l=0; [ -e /var/lib/pacman/db.lck ] && l=1; s=$(stat -c %s /var/log/pacman.log 2>/dev/null || echo 0); echo $l $s; "
            + "[ \"$1\" -ge 0 ] && tail -c +$(( $1 + 1 )) /var/log/pacman.log 2>/dev/null | grep -cE '\\[ALPM\\] (upgraded|installed|removed|downgraded|reinstalled) '; true",
            "pacman", String(Math.round(root.logStart))]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n");
                const head = (lines[0] ?? "").split(" ");
                const locked = head[0] === "1";
                const size = parseFloat(head[1]) || 0;
                if (locked && !root.busy) {
                    root.logStart = size;
                    root.count = 0;
                    root.busy = true;
                    return;
                }
                if (root.busy)
                    root.count = parseInt(lines[1] ?? "0") || 0;
                if (!locked && root.busy) {
                    root.busy = false;
                    root.logStart = -1;
                    root.finish(root.count);
                }
            }
        }
    }

    function finish(n: int): void {
        if (n <= 0 || !(Config.data.events.pacman ?? true))
            return;
        root.events.post({
            key: "pacman:done",
            glyph: "pacman",
            glyphArgs: { food: "box" },
            icon: String.fromCodePoint(0xf0baf),
            family: "nerd",
            color: "accentYellow",
            text: I18n.trN(n, "%1 package updated", "%1 packages updated")
        });
    }
}
