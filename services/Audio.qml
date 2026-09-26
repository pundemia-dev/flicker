import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "../config"

Scope {
    id: root

    readonly property real maxVolume: Config.data.audio.maxVolume
    readonly property real volumeStep: Config.data.audio.volumeStep

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource

    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: !!sink?.audio?.muted
    readonly property real sourceVolume: source?.audio?.volume ?? 0
    readonly property bool sourceMuted: !!source?.audio?.muted

    // Capture streams that count as "mic in use", in order of appearance
    // (stack: the last element is the newest stream and the one shown, so
    // closing it falls back to the previous one).
    property var captureStreams: []
    // Appearance-order keys for the stack. PipeWire object ids are stable
    // while a stream lives; node names are the fallback.
    property var streamOrder: []
    readonly property bool micActive: captureStreams.length > 0
    readonly property string micAppName: captureStreams.length > 0
        ? root.streamLabel(captureStreams[captureStreams.length - 1])
        : ""

    function streamKey(node: var): string {
        const id = node.id ?? null;
        if (id !== null && id !== undefined)
            return `id:${id}`;
        return `name:${node.name ?? ""}`;
    }

    function streamLabel(node: var): string {
        const props = node.properties ?? {};
        return props["application.name"] || props["application.process.binary"]
            || node.description || node.name || "Microphone";
    }

    function setVolume(value: real): void {
        if (sink?.ready && sink?.audio) {
            sink.audio.muted = false;
            sink.audio.volume = Math.max(0, Math.min(maxVolume, value));
        }
    }
    function incrementVolume(): void { setVolume(volume + volumeStep); }
    function decrementVolume(): void { setVolume(volume - volumeStep); }
    function toggleMute(): void {
        if (sink?.ready && sink?.audio)
            sink.audio.muted = !sink.audio.muted;
    }

    function setSourceVolume(value: real): void {
        if (source?.ready && source?.audio) {
            source.audio.muted = false;
            source.audio.volume = Math.max(0, Math.min(maxVolume, value));
        }
    }
    function toggleSourceMute(): void {
        if (source?.ready && source?.audio)
            source.audio.muted = !source.audio.muted;
    }

    // Spec: the mic indicator must NOT react to dictation (pw-record) or
    // screen recording (wf-recorder) — the shell's own capture streams are
    // filtered out of the mic-in-use detection.
    function isShellCapture(node: var): bool {
        const props = node.properties ?? {};
        const app = `${props["application.name"] ?? ""}`.toLowerCase();
        const bin = `${props["application.process.binary"] ?? ""}`.toLowerCase();
        const nm = `${node.name ?? ""}`.toLowerCase();
        return app === "pw-record" || app === "wf-recorder"
            || bin === "pw-record" || bin === "wf-recorder"
            || nm.indexOf("pw-record") !== -1 || nm.indexOf("wf-recorder") !== -1;
    }

    // User exclusion list (config.audio.micExclude): case-insensitive
    // substrings matched against application name, process binary,
    // description and node name. Hides DSP infrastructure nodes and the like
    // without hardcoding any setup-specific names; empty by default.
    // Bound (not read imperatively) so config hot-reload re-triggers the
    // filter below through onExcludePatternsChanged.
    readonly property var excludePatterns: Config.data.audio.micExclude ?? []
    onExcludePatternsChanged: root.refresh()
    function isExcluded(node: var): bool {
        if (root.isShellCapture(node))
            return true;
        const patterns = root.excludePatterns ?? [];
        if (!patterns || patterns.length === 0)
            return false;
        const props = node.properties ?? {};
        const hay = [`${props["application.name"] ?? ""}`,
            `${props["application.process.binary"] ?? ""}`,
            `${node.description ?? ""}`, `${node.name ?? ""}`].join("\n").toLowerCase();
        for (const p of patterns) {
            const pat = `${p ?? ""}`.toLowerCase();
            if (pat !== "" && hay.indexOf(pat) !== -1)
                return true;
        }
        return false;
    }

    function refresh(): void {
        const live = [];
        for (const node of Pipewire.nodes.values) {
            if (node.isStream && !node.isSink && node.audio && !root.isExcluded(node))
                live.push(node);
        }
        // Stack: drop gone streams, append newcomers at the end.
        const keys = live.map(n => root.streamKey(n));
        const order = root.streamOrder.filter(k => keys.indexOf(k) !== -1);
        for (const k of keys)
            if (order.indexOf(k) === -1)
                order.push(k);
        root.streamOrder = order;
        const byKey = {};
        for (const n of live)
            byKey[root.streamKey(n)] = n;
        root.captureStreams = order.map(k => byKey[k]).filter(n => n !== undefined);
    }

    Connections {
        target: Pipewire.nodes
        function onValuesChanged(): void { root.refresh(); }
    }

    PwObjectTracker {
        objects: root.captureStreams
    }
}
