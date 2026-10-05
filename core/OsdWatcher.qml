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
    property var haptics: null

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
    // Bound steps tick the trackpad (Config.haptics.osdSteps) when the
    // value reaches or passes a multiple of osdStepEvery percent (either
    // direction: up ticks on arrival at 10/20/..., down too); QS slider
    // moves never get here (quiet window), so they stay silent.
    function tick(from: real, to: real): void {
        const every = Config.data.haptics?.osdStepEvery ?? 10;
        if (!Config.data.haptics?.osdSteps || from < 0 || every <= 0)
            return;
        const a = Math.round(from * 100);
        const b = Math.round(to * 100);
        if (b > a ? Math.floor(b / every) * every > a : b < a && Math.ceil(b / every) * every < a)
            root.haptics?.tick();
    }
    function moved(a: real, b: real): bool {
        return a < 0 || Math.abs(a - b) > 0.004;
    }

    Connections {
        target: root.audio
        function onVolumeChanged(): void {
            const v = root.audio.volume;
            if (root.moved(root.lastVolume, v) && root.allowed(root.audio)) {
                root.island?.showOsd({ kind: "volume" });
                root.tick(root.lastVolume, v);
            }
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
                    && root.brightness.initialized && root.allowed(root.brightness)) {
                root.island?.showOsd({ kind: "brightness" });
                root.tick(root.lastBrightness, v);
            }
            root.lastBrightness = v;
        }
    }
}
