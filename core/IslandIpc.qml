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
    required property var capture
    required property var recorder
    required property var wallpaper
    required property var events
    required property var battery

    readonly property var island: root.registry.forOutput(root.compositor?.focusedOutput ?? "")

    IpcHandler {
        target: "island"
        function launcher(): void { root.island?.openLauncher(""); }
        // Launcher straight into a plugin (id from modules/launcher/plugins:
        // apps, clipboard, wallpapers); again while it is open closes it.
        function launcherPlugin(id: string): void { root.island?.openLauncher(id); }
        // Random wallpaper on the focused output (config randomFrom).
        function wallpaperRandom(): void { root.wallpaper.random(root.island?.targetScreen?.name ?? ""); }
        // Slideshow on/off (over all wallpapers; Ctrl+S in the carousel
        // starts it over the current view) / one step now.
        function wallpaperSlideshow(): void { root.wallpaper.slideshow.toggle(null); }
        function wallpaperNext(): void { root.wallpaper.slideshow.next(); }
        function quicksettings(): void { root.island?.openQuickSettings(); }
        // Quick Settings straight into edit mode (= long press on a card).
        function quicksettingsEdit(): void {
            root.island?.openQuickSettings();
            root.island?.controlCenter.beginEdit();
        }
        // QS tab by index (rail tap) / card footprint (= the resize arc;
        // used to test the morphs without a pointer).
        function quicksettingsPage(index: int): void { root.island?.controlCenter.setPage(index); }
        function quicksettingsResize(id: string, w: int, h: int): void {
            const cc = root.island?.controlCenter;
            cc?.previewResize(id, w, h);
            cc?.commit();
            cc?.save();
        }
        function notifications(): void { root.island?.openNotificationCenter(); }
        function capture(): void { root.island?.openCapture(""); }
        // shot | record | color | window | ai | scan (while open: switch to it).
        function captureMode(mode: string): void { root.island?.openCapture(mode); }
        // While capturing: the active screen's main action (Enter) / abort.
        function captureScreen(): void { root.capture.confirm(); }
        function captureCancel(): void { root.capture.cancel(); }
        // Instant full-output screenshot of the focused output, no overlay.
        function screenshot(): void { root.capture.actions.screenshotOutput(root.island?.screen?.name ?? ""); }
        // Recording: toggle (stop, or open capture in record mode) / pause.
        function record(): void {
            if (root.recorder.recording)
                root.recorder.stop();
            else
                root.island?.openCapture("record");
        }
        function recordPause(): void { root.recorder.togglePause(); }
        // Recording controls in the island (= clicking the red clock plate).
        function recordControls(): void {
            if (root.recorder.recording)
                root.island?.openModule("recording-actions", {});
        }
        function dashboard(): void { root.island?.openDashboard(); }
        // File tray (toggle). The drop chooser opens on its own when a file
        // is dragged over the island.
        function stash(): void { root.island?.toggleStash(); }
        function player(): void { root.island?.openModule("player", {}); }
        function lock(): void { root.lock.activate(); }
        function close(): void {
            if (root.island?.moduleOpen)
                root.island.closeModule();
        }
        function minimal(): void { root.island?.state.setMinimal(); }
        function island(): void { root.island?.state.setIsland(); }
        function osd(title: string, icon: string, value: real): void { root.island?.showOsd({ kind: "custom", icon: icon, value: value }); }

        // Key-driven OSD (bind in niri: qs -c pillShell ipc call island <fn>)
        // Value keys: just change the value — core/OsdWatcher shows the OSD
        // for ANY change (also wpctl/brightnessctl bound in the compositor).
        // A press that cannot move the value (at an end) produces no change
        // signal, so it is shown here with `push` (-1 low / +1 high) and the
        // track rubber-bands.
        function volumeUp(): void {
            if (root.audio.volume >= root.audio.maxVolume - 0.001)
                root.island?.showOsd({ kind: "volume", push: 1 });
            root.audio.incrementVolume();
        }
        function volumeDown(): void {
            if (root.audio.volume <= 0.001)
                root.island?.showOsd({ kind: "volume", push: -1 });
            root.audio.decrementVolume();
        }
        function volumeMute(): void { root.audio.toggleMute(); }
        function micMute(): void { root.audio.toggleSourceMute(); }
        function brightnessUp(): void {
            if (root.brightness.brightness >= 0.999)
                root.island?.showOsd({ kind: "brightness", push: 1 });
            root.brightness.increase();
        }
        function brightnessDown(): void {
            // brightnessctl floor is 1%.
            if (root.brightness.brightness <= 0.011)
                root.island?.showOsd({ kind: "brightness", push: -1 });
            root.brightness.decrease();
        }
        function playPause(): void { root.players.playPause(); }
        function nextTrack(): void { root.players.next(); }
        function prevTrack(): void { root.players.previous(); }
        // Absolute seek (s) on the active player — same write as the seek bars.
        function playerSeek(seconds: real): void {
            const p = root.players.active;
            if (p?.canSeek && p?.positionSupported)
                p.position = Math.max(0, seconds);
        }

        // Runtime introspection of the routed island (headless debugging).
        // Event indicator demo (no real source needed): charging | discharging |
        // bluetooth | pacman | aur | text <anything else = the text>.
        function eventDemo(kind: string): void {
            const demos = {
                charging: { key: "charging", icon: "\uea38", color: "batteryGood", texts: [() => `${root.battery.percent}%`, "1 h 25 min"] },
                discharging: { key: "discharging", icon: "\uecec", color: "accentOrange", texts: [() => `${root.battery.percent}%`, "4 h 10 min"] },
                bluetooth: { key: "bt:demo", icon: "\ueabd", color: "qsBlue", text: "87%" },
                pacman: { key: "updates:pacman", icon: String.fromCodePoint(0xf0baf), glyph: "pacman", color: "accentYellow", family: "nerd", text: "12" },
                aur: { key: "updates:aur", icon: "\uf4a2", glyph: "ghost", color: "qsBlue", family: "nerd", text: "3" }
            };
            root.events.post(demos[kind] ?? { key: `demo:${kind}`, icon: "\uea37", text: kind });
        }
        function debugState(): string { return root.island?.debugState() ?? "{}"; }
    }
}
