import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "../config"

Scope {
    id: root

    // Headphone-like current output (AudioPolicy binds it): its own cap,
    // audio.maxVolumeHeadphones (0 = the same as maxVolume).
    property bool personalOutput: false
    readonly property real maxVolume: root.personalOutput && (Config.data.audio.maxVolumeHeadphones ?? 0) > 0
        ? Config.data.audio.maxVolumeHeadphones : Config.data.audio.maxVolume
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

    // OsdWatcher skips changes until this timestamp: UI sliders call quiet()
    // (spec: no OSD for Quick Settings changes); a default-device switch is
    // quiet too (headphones plugged -> the new sink's volume is no "change").
    property real osdQuietUntil: 0
    function quiet(): void {
        root.osdQuietUntil = Date.now() + Config.data.osd.quietMs;
    }
    onSinkChanged: {
        root.quiet();
        Qt.callLater(root.restoreVolume);
    }
    onSourceChanged: root.quiet()

    // Hard cap (audio.maxVolume): changes from outside the shell (wpctl in
    // compositor binds, pavucontrol, apps) are pulled back to the limit too.
    // Deferred: writing the volume inside its own change handler is a
    // binding loop on `volume`.
    onVolumeChanged: {
        Qt.callLater(root.enforceCap);
        root.queueVolumeSave();
    }
    onMaxVolumeChanged: Qt.callLater(root.enforceCap)
    function enforceCap(): void {
        if (sink?.ready && sink?.audio && sink.audio.volume > maxVolume + 0.001)
            sink.audio.volume = maxVolume;
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
            || nm.indexOf("pw-record") !== -1 || nm.indexOf("wf-recorder") !== -1
            // record.sh: its parecord stream (client flicker_rec_audio)
            // and the "both" mode mic/system loopbacks into the mix sink.
            || app.indexOf("flicker_rec") !== -1 || nm.indexOf("flicker_rec") !== -1
            // components/AudioBars: cava on the output monitor.
            || app === "cava" || bin === "cava" || nm === "cava"
            // PwNodePeakMonitor (QS audio panel's mic level): Quickshell's
            // own capture stream, node "quickshell".
            || nm === "quickshell" || app === "quickshell"
            // AudioPolicy: voice processing, listen to yourself.
            || nm.startsWith("flicker_");
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

    // Output volume + mute per sink (node name) persist in
    // statePath("volume.json") (any change, 1 s debounce) and are re-applied
    // once per login (marker in $XDG_RUNTIME_DIR: a hot reload inside the
    // debounce would restore a stale level): every sink that is the default
    // within restoreWindowMs of start gets its level once (WirePlumber may
    // expose a dummy / HDMI sink before the speakers). WirePlumber's own
    // route state did not keep the T2 speakers' level. Later device switches
    // are WirePlumber's (a BT headset may have changed its level elsewhere).
    property var savedVolumes: ({})
    readonly property int restoreWindowMs: 20000
    property real restoreUntil: 0
    property var restoredSinks: []
    readonly property bool sinkReady: !!(sink?.ready && sink?.audio)
    onSinkReadyChanged: Qt.callLater(root.restoreVolume)
    Component.onCompleted: {
        if (volumeMarker.claim())
            root.restoreUntil = Date.now() + root.restoreWindowMs;
        Qt.callLater(root.restoreVolume);
    }
    onMutedChanged: root.queueVolumeSave()
    // Not before the sink got its saved level (it would overwrite it).
    function canSaveVolume(): bool {
        return root.sinkReady && !!root.sink.name
            && (Date.now() > root.restoreUntil || root.restoredSinks.includes(root.sink.name));
    }
    // The level is taken now, per sink: a default-sink switch inside the
    // debounce must not save the new sink's level (or nothing) instead.
    property var pendingVolumes: ({})
    function queueVolumeSave(): void {
        if (!root.canSaveVolume())
            return;
        const next = Object.assign({}, root.pendingVolumes);
        next[root.sink.name] = { volume: root.volume, muted: root.muted };
        root.pendingVolumes = next;
        volumeSave.restart();
    }
    function restoreVolume(): void {
        if (!root.sinkReady || Date.now() > root.restoreUntil)
            return;
        const name = root.sink.name ?? "";
        if (root.restoredSinks.includes(name))
            return;
        root.restoredSinks = [...root.restoredSinks, name];
        const v = root.savedVolumes[name];
        if (!v || typeof v.volume !== "number" || !(Config.data.persist?.volume ?? true))
            return;
        root.quiet();
        root.sink.audio.volume = Math.max(0, Math.min(root.maxVolume, v.volume));
        root.sink.audio.muted = !!v.muted;
    }
    LoginOnce {
        id: volumeMarker
        name: "volume"
    }
    Timer {
        id: volumeSave
        interval: 1000
        onTriggered: {
            const next = Object.assign({}, root.savedVolumes, root.pendingVolumes);
            root.pendingVolumes = {};
            root.savedVolumes = next;
            volumeFile.write({ sinks: next });
        }
    }
    StateFile {
        id: volumeFile
        name: "volume.json"
        onLoaded: {
            const sinks = volumeFile.read().sinks;
            root.savedVolumes = sinks && typeof sinks === "object" ? sinks : {};
        }
    }

    // Default sink/source must be tracked too: an unbound node never turns
    // `ready` and its `audio` props read 0 (volume keys were silent no-ops).
    PwObjectTracker {
        objects: [root.sink, root.source, ...root.captureStreams].filter(n => !!n)
    }
}
