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
// Nothing pending -> no event.
Scope {
    id: root
    required property var events

    Timer {
        running: Config.data.events.updates ?? true
        interval: Config.data.events.updatesDelayMs
        onTriggered: check.running = true
    }

    Process {
        id: check
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
        root.events.post({ key, icon, glyph: glyph ?? "", color, family: "nerd", text: `${count}` });
    }
}
