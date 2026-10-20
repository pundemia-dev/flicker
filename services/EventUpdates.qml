import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Event source: pending updates, once per session `updatesDelayMs` after
// start (the network is up by then). Two events in a row: pacman first,
// then the AUR (the FIFO shows the second when the first is gone). Glyphs
// = the user's show_updates script (Nerd Font: md-pac_man, oct-smiley);
// pacman / AUR are drawn + animated (indicators/PacmanGlyph.qml,
// GhostGlyph.qml — the ghost follows pacman), the font glyph
// stays as the fallback.
// Nothing pending -> no event. Tap = the `updates` module (event `open`).
// Only after a boot, not a shell restart: the system uptime at shell start
// must be <= updatesMaxUptimeSec (0 = check on every start).
// Low Power Mode (services/PowerMode, Config.powerSave.deferUpdates) holds
// the check until the mode is off.
Scope {
    id: root
    required property var events
    property var powerMode: null
    // Read once at start: a restart later in the session never qualifies.
    property bool freshBoot: false

    Process {
        running: true
        command: ["cat", "/proc/uptime"]
        stdout: StdioCollector {
            onStreamFinished: {
                const up = parseFloat(this.text) || 0;
                const max = Config.data.events.updatesMaxUptimeSec ?? 180;
                root.freshBoot = max <= 0 || up <= max;
            }
        }
    }

    Timer {
        running: root.freshBoot && !check.done && (Config.data.events.updates ?? true)
            && !((root.powerMode?.active ?? false) && (Config.data.powerSave.deferUpdates ?? true))
        interval: Config.data.events.updatesDelayMs
        onTriggered: check.running = true
    }

    Process {
        id: check
        property bool done: false
        onStarted: check.done = true
        command: ["sh", "-c", "checkupdates 2>/dev/null | wc -l; { yay -Qua 2>/dev/null || paru -Qua 2>/dev/null; } | wc -l"]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = this.text.trim().split("\n").map(s => parseInt(s) || 0);
                root.announce("updates:pacman", String.fromCodePoint(0xf0baf), "accentYellow", n[0] ?? 0, "pacman");
                root.announce("updates:aur", "", "qsBlue", n[1] ?? 0, "ghost");
            }
        }
    }

    function announce(key: string, icon: string, color: string, count: int, glyph: string): void {
        if (count <= 0)
            return;
        root.events.post({ key, icon, glyph: glyph ?? "", color, family: "nerd", text: `${count}`, open: "updates" });
    }
}
