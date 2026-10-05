import QtQuick
import Quickshell
import "../config"

// Shows the OSD on ANY volume / mute / brightness change, whoever made it
// (caelestia/DMS/end-4 pattern): compositor binds can run wpctl and
// brightnessctl directly, so the keys keep working with the shell down and
// the island just reflects the change. Changes made from the shell's own
// sliders are skipped through the services' `osdQuietUntil` window (spec:
// no OSD for Quick Settings changes), as is the start-up value load.
Scope {
    id: root

    required property var registry
    required property var compositor
    required property var audio
    required property var brightness

    readonly property var cfg: Config.data.osd
    readonly property var island: root.registry.forOutput(root.compositor?.focusedOutput ?? "")
    property real startedAt: Date.now()

    // Last seen values: PipeWire re-emits on unrelated param updates, only
    // a real move counts. -1 = never seen (a value that was already in place
    // at start-up never signals; the start-up quiet window covers the load).
    property real lastVolume: -1
    property bool lastMuted: false
    property real lastSourceVolume: -1
    property bool lastSourceMuted: false
    property real lastBrightness: -1

    function allowed(service: var): bool {
        const now = Date.now();
        return root.cfg.watch && now - root.startedAt >= root.cfg.startupQuietMs
            && now >= (service?.osdQuietUntil ?? 0);
    }
    function moved(a: real, b: real): bool {
        return a < 0 || Math.abs(a - b) > 0.004;
    }

    Connections {
        target: root.audio
        function onVolumeChanged(): void {
            const v = root.audio.volume;
            if (root.moved(root.lastVolume, v) && root.allowed(root.audio))
                root.island?.showOsd({ kind: "volume" });
            root.lastVolume = v;
        }
        function onMutedChanged(): void {
            if (root.audio.muted !== root.lastMuted && root.allowed(root.audio))
                root.island?.showOsd({ kind: "volume" });
            root.lastMuted = root.audio.muted;
        }
        function onSourceVolumeChanged(): void {
            const v = root.audio.sourceVolume;
            if (root.cfg.watchMicVolume && root.moved(root.lastSourceVolume, v) && root.allowed(root.audio))
                root.island?.showOsd({ kind: "mic" });
            root.lastSourceVolume = v;
        }
        function onSourceMutedChanged(): void {
            if (root.audio.sourceMuted !== root.lastSourceMuted && root.allowed(root.audio))
                root.island?.showOsd({ kind: "mic" });
            root.lastSourceMuted = root.audio.sourceMuted;
        }
    }

    Connections {
        target: root.brightness
        function onBrightnessChanged(): void {
            const v = root.brightness.brightness;
            if (root.moved(root.lastBrightness, v)
                    && root.brightness.initialized && root.allowed(root.brightness))
                root.island?.showOsd({ kind: "brightness" });
            root.lastBrightness = v;
        }
    }
}
