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
    required property var caffeine
    required property var charging
    required property var countdown
    required property var keyboard
    required property var shazam
    required property var statuses
    required property var network
    required property var audioOutput
    required property var batteryEvents
    required property var displays
    required property var drives
    required property var downloads

    // Drawn glyph previews for IPC glyphDemo: name -> [Theme colour, text].
    readonly property var glyphDemos: ({
            bluetooth: ["qsBlue", "Connected"],
            airpods: ["qsBlue", "87%"],
            airpodsMax: ["qsBlue", "64%"],
            speaker: ["qsBlue", "HomePod"],
            phone: ["qsBlue", "iPhone"],
            tablet: ["qsBlue", "iPad"],
            laptop: ["qsBlue", "MacBook"],
            watch: ["qsBlue", "92%"],
            mouse: ["qsBlue", "71%"],
            keyboard: ["qsBlue", "58%"],
            gamepad: ["qsBlue", "45%"],
            lock: ["batteryGood", "VPN"],
            moon: ["focusPurple", "Focus"],
            transfer: ["qsBlue", "3 files"],
            parcels: ["accentYellow", "Installing"],
            error: ["accentRed", "2 failed"],
            copy: ["batteryGood", "Copied"],
            pacman: ["accentYellow", "12"],
            ghost: ["qsBlue", "3"],
            coffee: ["coffee", "On"],
            bolt: ["batteryGood", "95%"],
            wifi: ["qsBlue", "Home"],
            battery: ["batteryGood", "Charged"],
            display: ["qsBlue", "DELL U2720Q"],
            drive: ["qsBlue", "KINGSTON"]
        })

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
        // Debug: long-press expansion of a QS card ("" = fold it back).
        // Debug: tile menu of stash file <i> (-1 folds it back).
        function stashMenu(i: int): void { root.island?.moduleItem?.debugMenu?.(i); }
        function quicksettingsExpand(id: string): void { root.island?.moduleItem?.expandCard?.(id); }
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
        // Transcript view of a file (WhisperX, queued if not done yet).
        function stashTranscript(path: string): void { root.island?.openTranscript(path); }
        // Quick Look of a file (any path; ← / → walk the tray).
        function stashPreview(path: string): void { root.island?.openModule("stash", { view: "preview", file: path, returnView: "tray" }); }
        function player(): void { root.island?.openModule("player", {}); }
        function lock(): void { root.lock.activate(); }
        // Session menu (lock / log out / sleep / restart / shut down), toggle.
        function session(): void { root.island?.toggleSession(); }
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
        // Charger events through the REAL handler (cancel + post), no cable.
        function chargerSim(plugged: bool): void { root.charging.announce(plugged); }
        // Timer module (setup / countdown); again while open closes it.
        function timer(): void { root.island?.openTimer(null); }
        // Start a countdown of n minutes without the module (1..maxMinutes).
        function timerStart(minutes: int): void { root.countdown.start(minutes); }
        // Pause / resume, cancel.
        function timerPause(): void { root.countdown.toggle(); }
        function timerCancel(): void { root.countdown.cancel(); }
        // Caffeine mode (idle inhibit) on/off.
        function caffeine(): void { root.caffeine.toggle(); }
        // Music recognition: start listening / cancel a running one.
        function shazam(): void { root.shazam.toggle(); }
        // Keyboard pill preview: "layout" = flash the current layout,
        // "caps" = toggle a fake Caps Lock (the LED poll restores the truth).
        function keyboardDemo(kind: string): void { root.keyboard.demo(kind); }
        // Event indicator demo (no real source needed): charging | discharging |
        // bluetooth | pacman | aur | wifi | wifiLost | output | full | critical |
        // display | displayOff | drive | driveOff | downloaded | text
        // <anything else = the text>.
        function eventDemo(kind: string): void {
            const demos = {
                charging: { key: "charging", icon: "\uea38", glyph: "bolt", glyphArgs: { mode: "join" }, color: () => root.battery.levelTone, texts: [() => `${root.battery.percent}%`, "1 h 25 min"] },
                discharging: { key: "discharging", icon: "\uecec", glyph: "bolt", glyphArgs: { mode: "break" }, color: () => root.battery.levelTone, texts: [() => `${root.battery.percent}%`, "4 h 10 min"] },
                bluetooth: { key: "bt:demo", icon: "\ueabd", color: "qsBlue", text: "87%" },
                pacman: { key: "updates:pacman", icon: String.fromCodePoint(0xf0baf), glyph: "pacman", color: "accentYellow", family: "nerd", text: "12" },
                aur: { key: "updates:aur", icon: "\uf4a2", glyph: "ghost", color: "qsBlue", family: "nerd", text: "3" }
            };
            // Real announcers (same code path as the live sources).
            const real = {
                wifi: () => root.network.announce(true, "Demo Wi‑Fi", true),
                wifiLost: () => root.network.announce(false, "", true),
                output: () => root.audioOutput.announce("headphones", "Headphones"),
                full: () => root.batteryEvents.announceFull(),
                critical: () => root.batteryEvents.announceCritical(),
                display: () => root.displays.announce("DP-1", "DELL U2720Q", "2560×1440", true),
                displayOff: () => root.displays.announce("DP-1", "DELL U2720Q", "", false),
                drive: () => root.drives.announce("/dev/demo1", "KINGSTON", "32 GB", true),
                driveOff: () => root.drives.announce("/dev/demo1", "KINGSTON", "", false),
                downloaded: () => root.downloads.announceDone("/tmp/demo.zip", "demo.zip")
            };
            if (real[kind]) {
                real[kind]();
                return;
            }
            root.events.post(demos[kind] ?? { key: `demo:${kind}`, icon: "\uea37", text: kind });
        }
        // Drawn glyph previews (no service needed): `glyphDemo <name>` posts
        // an event with that glyph; `glyphDemoAll` queues every one.
        function glyphDemo(name: string): void {
            const d = root.glyphDemos[name];
            if (!d)
                return;
            root.events.post({
                key: `glyph:${name}`,
                glyph: name === "parcels" ? "pacman" : name,
                glyphArgs: name === "parcels" ? { food: "box" } : (name === "bolt" ? { mode: "break" } : {}),
                icon: "\uea37",
                color: d[0],
                text: d[1]
            });
        }
        function glyphDemoAll(): void {
            for (const name of Object.keys(root.glyphDemos))
                glyphDemo(name);
        }
        // Status drop demo: `statusDemo <name> <percent>` posts a status
        // "demo:<name>" (percent < 0 = indeterminate) + its start event;
        // again = update in place; `statusDemoEnd <name>` drops it;
        // `statusNext` = the swipe on the drop.
        function statusDemo(name: string, percent: int): void {
            const key = `demo:${name}`;
            const colors = ["qsBlue", "accentGreen", "focusPurple", "accentRed", "accentYellow"];
            const fresh = !root.statuses.find(key);
            root.statuses.post({
                key: key,
                priority: 5,
                color: colors[Math.abs(name.split("").reduce((h, c) => h * 31 + c.charCodeAt(0), 7)) % colors.length],
                progress: percent < 0 ? null : percent / 100,
                open: ""
            });
            if (fresh)
                root.events.post({ key: `status:${key}`, status: key, icon: "", text: name });
        }
        function statusDemoEnd(name: string): void { root.statuses.cancel(`demo:${name}`); }
        function statusNext(): void { root.statuses.cycle(1); }
        function debugState(): string { return root.island?.debugState() ?? "{}"; }
    }
}
