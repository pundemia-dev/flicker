import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Event source: the audio output changed — another default sink (USB DAC,
// HDMI, a filter chain) OR another active port on the same sink (wired
// headphones into the jack usually only switch the port, the node stays).
// `pactl subscribe` wakes a debounced re-read of `pactl -f json list sinks`;
// the signature default-sink|active-port must differ from the last one.
// OSD stays quiet on a sink switch (OsdWatcher), so this is the only
// feedback. Bluetooth sinks are skipped: EventBluetooth already announced
// the device. Text: the output's name, then the live volume rolls in.
Scope {
    id: root
    required property var events
    required property var audio

    property string signature: ""
    property bool armed: false
    Timer {
        running: true
        interval: Config.data.events.startupQuietMs
        onTriggered: root.armed = true
    }

    Process {
        id: watch
        running: true
        command: ["pactl", "subscribe"]
        stdout: SplitParser {
            onRead: line => {
                if (line.indexOf("on sink #") !== -1 || line.indexOf("on server") !== -1)
                    debounce.restart();
            }
        }
        // pipewire-pulse restarted: subscribe again after a moment.
        onExited: respawn.restart()
    }
    Timer {
        id: respawn
        interval: 3000
        onTriggered: watch.running = true
    }
    Timer {
        id: debounce
        interval: Config.data.events.audioOutputSettleMs ?? 400
        onTriggered: query.running = true
    }
    Component.onCompleted: query.running = true

    Process {
        id: query
        command: ["sh", "-c", "pactl get-default-sink; pactl -f json list sinks"]
        stdout: StdioCollector {
            onStreamFinished: root.parse(this.text)
        }
    }

    function parse(text: string): void {
        const nl = text.indexOf("\n");
        const name = text.slice(0, nl).trim();
        let sinks = [];
        try {
            sinks = JSON.parse(text.slice(nl + 1));
        } catch (e) {
            return;
        }
        const sink = sinks.find(s => s.name === name);
        if (!sink)
            return;
        const portName = sink.active_port ?? "";
        const port = (sink.ports ?? []).find(p => p.name === portName) ?? null;
        const sig = `${name}|${portName}`;
        const changed = root.signature !== "" && sig !== root.signature;
        root.signature = sig;
        if (!changed || !root.armed || !(Config.data.events.audioOutput ?? true))
            return;
        const props = sink.properties ?? {};
        if ((props["device.bus"] ?? "") === "bluetooth" || name.startsWith("bluez_"))
            return;
        root.announce(root.kindOf(name, props, port), root.labelOf(sink, port));
    }

    // headphones | display | speaker | laptop (built-in speakers).
    function kindOf(name: string, props: var, port: var): string {
        const hay = [name, port?.name ?? "", port?.type ?? "", port?.description ?? "", props["device.icon_name"] ?? "",
            props["device.form_factor"] ?? ""].join(" ").toLowerCase();
        if (/headphone|headset|earbud|analog-output-headphones/.test(hay))
            return "headphones";
        if (/hdmi|displayport|\bdp\b|iec958-stereo/.test(hay))
            return "display";
        if ((props["device.bus"] ?? "") === "usb" || /usb/.test(hay))
            return "speaker";
        return "laptop";
    }

    function labelOf(sink: var, port: var): string {
        // A real port name ("Headphones") says more than a long card name.
        const generic = /^(speaker|analog output|output)$/i;
        const p = port?.description ?? "";
        const label = p && !generic.test(p) && (sink.ports ?? []).length > 1 ? p : (sink.description ?? "");
        const max = Config.data.events.audioOutputMaxChars ?? 24;
        return label.length > max ? label.slice(0, max - 1).replace(/\s+$/, "") + "…" : label;
    }

    // Also IPC `island eventDemo output`.
    function announce(kind: string, label: string): void {
        root.events.post({
            key: "audioOutput",
            glyph: kind,
            icon: "",
            color: "qsBlue",
            texts: [label, () => root.audio.muted ? I18n.tr("Muted") : `${Math.round(root.audio.volume * 100)}%`]
        });
    }
}
