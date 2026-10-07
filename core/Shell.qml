import QtQuick
import Quickshell
import "../config"
import "../services"
import "../compositor"
import "../modules/lock"
import "../modules/capture"

Scope {
    id: root

    Theme { id: themeService }
    Clock { id: clockService }
    Audio { id: audioService }
    Players { id: playersService }
    Network { id: networkService }
    Bluetooth { id: bluetoothService }
    Battery { id: batteryService }
    Brightness { id: brightnessService }
    Notifications { id: notificationsService }
    Recorder { id: recorderService }
    Dictation { id: dictationService; keyboardLayout: keyboardLayoutService }
    KeyboardLayout { id: keyboardLayoutService }
    // Teleprompter: shows on the focused output (Island.openPrompter).
    Prompter {
        id: prompterService
        dictation: dictationService
        onShowRequested: islandRegistry.forOutput(compositorService.focusedOutput ?? "")?.openPrompter()
    }
    SystemUsage { id: systemUsageService }
    Sensors { id: sensorsService }
    Weather { id: weatherService }
    Haptics { id: hapticsService }
    Stash { id: stashService; cfg: Config.data.stash }
    // Polkit agent: a request opens the prompt on the focused output.
    Polkit {
        id: polkitService
        cfg: Config.data.polkit
        haptics: hapticsService
        onStarted: islandRegistry.forOutput(compositorService.focusedOutput ?? "")?.openPolkit()
    }
    ControlCenter { id: controlCenterService; cfg: Config.data.quicksettings; haptics: hapticsService }
    LocalSend {
        id: localSendService
        cfg: Config.data.stash
        stashDir: stashService.stashDir
        // Received files are mirrored into the tray: show them right away.
        onFileReceived: stashService.refresh()
        // An incoming transfer needs a decision: the accept card opens on
        // the focused output (only while receiving is switched on).
        onRequestArrived: islandRegistry.forOutput(compositorService.focusedOutput ?? "")?.openStash("incoming")
    }

    // Recording is WM-agnostic: the facade delegates to the Recorder service.
    Compositor {
        id: compositorService
        recorder: recorderService
    }

    LockScope { id: lockScope }

    CaptureScope {
        id: captureService
        recorder: recorderService
        theme: themeService
        compositor: compositorService
    }

    IslandRegistry { id: islandRegistry }

    // Wallpapers (wallr): favourites/history, random, video pause.
    Wallpaper {
        id: wallpaperService
        compositor: compositorService
        battery: batteryService
    }

    IslandIpc {
        registry: islandRegistry
        compositor: compositorService
        audio: audioService
        brightness: brightnessService
        players: playersService
        lock: lockScope
        capture: captureService
        recorder: recorderService
        wallpaper: wallpaperService
    }

    OsdWatcher {
        registry: islandRegistry
        haptics: hapticsService
        compositor: compositorService
        audio: audioService
        brightness: brightnessService
    }

    Variants {
        model: Quickshell.screens

        delegate: Scope {
            required property ShellScreen modelData

            Island {
                targetScreen: modelData
                registry: islandRegistry
                config: Config.data
                theme: themeService
                compositor: compositorService
                clock: clockService
                audio: audioService
                players: playersService
                network: networkService
                bluetooth: bluetoothService
                battery: batteryService
                brightness: brightnessService
                notifications: notificationsService
                recorder: recorderService
                dictation: dictationService
                systemUsage: systemUsageService
                sensors: sensorsService
                weather: weatherService
                lock: lockScope
                capture: captureService
                stash: stashService
                localSend: localSendService
                controlCenter: controlCenterService
                haptics: hapticsService
                polkit: polkitService
                prompter: prompterService
                wallpaper: wallpaperService
            }

            Corners {
                targetScreen: modelData
                visible: !lockScope.locked
            }
        }
    }
}
