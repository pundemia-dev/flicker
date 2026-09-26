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

    property var captureStreams: []
    readonly property bool micActive: captureStreams.length > 0
    readonly property string micAppName: captureStreams.length > 0
        ? (captureStreams[0].properties["application.name"] || captureStreams[0].description || captureStreams[0].name || "Microphone")
        : ""

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

    Connections {
        target: Pipewire.nodes
        function onValuesChanged(): void {
            const streams = [];
            for (const node of Pipewire.nodes.values) {
                if (node.isStream && !node.isSink && node.audio && !root.isShellCapture(node))
                    streams.push(node);
            }
            root.captureStreams = streams;
        }
    }

    PwObjectTracker {
        objects: root.captureStreams
    }
}
