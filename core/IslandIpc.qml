import QtQuick
import Quickshell
import Quickshell.Io

// The single "island" IPC target. One handler per shell, not per screen:
// duplicate targets made the call land on an arbitrary island. Commands go
// to the island on the compositor's focused output (spec: modules open on
// the current monitor only).
Scope {
    id: root
    required property var registry
    required property var compositor
    required property var audio
    required property var brightness
    required property var players
    required property var lock

    readonly property var island: root.registry.forOutput(root.compositor?.focusedOutput ?? "")

    IpcHandler {
        target: "island"
        function launcher(): void { root.island?.openLauncher(); }
        function quicksettings(): void { root.island?.openQuickSettings(); }
        function notifications(): void { root.island?.openNotificationCenter(); }
        function capture(): void { root.island?.openCapture(); }
        function dashboard(): void { root.island?.openModule("dashboard", {}); }
        function player(): void { root.island?.openModule("player", {}); }
        function lock(): void { root.lock.activate(); }
        function close(): void {
            if (root.island?.moduleOpen)
                root.island.closeModule();
        }
        function minimal(): void { root.island?.state.setMinimal(); }
        function island(): void { root.island?.state.setIsland(); }
        function osd(title: string, icon: string, value: real): void { root.island?.showOsd(title, icon, value); }

        // Key-driven OSD (bind in niri: qs -c pillShell ipc call island <fn>)
        function volumeUp(): void {
            root.audio.incrementVolume();
            root.island?.showOsd("Volume", root.audio.muted ? "🔇" : "🔊", root.audio.volume);
        }
        function volumeDown(): void {
            root.audio.decrementVolume();
            root.island?.showOsd("Volume", root.audio.muted ? "🔇" : "🔊", root.audio.volume);
        }
        function volumeMute(): void {
            root.audio.toggleMute();
            root.island?.showOsd("Volume", root.audio.muted ? "🔇" : "🔊", root.audio.volume);
        }
        function micMute(): void {
            root.audio.toggleSourceMute();
            root.island?.showOsd("Microphone", "🎙", root.audio.sourceMuted ? 0 : root.audio.sourceVolume);
        }
        function brightnessUp(): void {
            root.brightness.increase();
            root.island?.showOsd("Brightness", "☀", root.brightness.brightness);
        }
        function brightnessDown(): void {
            root.brightness.decrease();
            root.island?.showOsd("Brightness", "☀", root.brightness.brightness);
        }
        function playPause(): void { root.players.playPause(); }
        function nextTrack(): void { root.players.next(); }
        function prevTrack(): void { root.players.previous(); }

        // Runtime introspection of the routed island (headless debugging).
        function debugState(): string { return root.island?.debugState() ?? "{}"; }
    }
}
