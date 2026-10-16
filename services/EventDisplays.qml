import QtQuick
import Quickshell
import "../config"

// Event source: a monitor connected / disconnected (Quickshell.screens
// changed; DisplayGlyph). Text = the model (or the output name), then the
// resolution on connect / "Disconnected" on removal. The island of a new
// output is created by Shell's Variants at the same moment — the event
// goes through the shared Events service, so every island shows it.
QtObject {
    id: root
    required property var events

    readonly property var screens: Quickshell.screens
    property var known: ({})
    property bool armed: false
    property Timer arm: Timer {
        running: true
        interval: Config.data.events.startupQuietMs
        onTriggered: {
            root.known = root.snapshot();
            root.armed = true;
        }
    }

    function snapshot(): var {
        const m = {};
        for (const s of root.screens)
            m[s.name] = { label: (s.model ?? "") || s.name, size: `${Math.round(s.width)}×${Math.round(s.height)}` };
        return m;
    }

    onScreensChanged: {
        if (!root.armed)
            return;
        const now = root.snapshot();
        if (Config.data.events.displays ?? true) {
            for (const name in now)
                if (!root.known[name])
                    root.announce(name, now[name].label, now[name].size, true);
            for (const name in root.known)
                if (!now[name])
                    root.announce(name, root.known[name].label, "", false);
        }
        root.known = now;
    }

    // Also IPC `island eventDemo display|displayOff`.
    function announce(name: string, label: string, size: string, connected: bool): void {
        root.events.cancel(`display:${connected ? "off" : "on"}:${name}`);
        root.events.post({
            key: `display:${connected ? "on" : "off"}:${name}`,
            glyph: "display",
            glyphArgs: connected ? {} : { off: true },
            icon: "",
            color: connected ? "qsBlue" : "islandFg",
            texts: connected && size ? [label, size] : [label, I18n.tr("Disconnected")]
        });
    }
}
