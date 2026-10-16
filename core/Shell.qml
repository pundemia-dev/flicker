import QtQuick
import Quickshell
import "../config"
import "../services"
import "../compositor"
import "../modules/lock"
import "../modules/capture"
import "../modules/keyboard"

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
    Privacy { id: privacyService; audio: audioService }
    // Event indicators (one at a time in the bar) + their sources.
    Events { id: eventsService }
    EventCharging { id: eventChargingService; events: eventsService; battery: batteryService }
    EventBluetooth { events: eventsService; bluetooth: bluetoothService }
    EventUpdates { events: eventsService }
    Caffeine { id: caffeineService; events: eventsService }
    EventNetwork { id: eventNetworkService; events: eventsService; network: networkService }
    EventAudioOutput { id: eventAudioOutputService; events: eventsService; audio: audioService }
    EventBattery { id: eventBatteryService; events: eventsService; battery: batteryService; charging: eventChargingService }
    EventDisplays { id: eventDisplaysService; events: eventsService }
    EventDrives { id: eventDrivesService; events: eventsService }
    // Long-process watchers for the status drop (StatusFeeds).
    PacmanWatch { id: pacmanWatchService; events: eventsService }
    DownloadWatch { id: downloadWatchService; events: eventsService }
    // Clipboard history feed (cliphist) for the launcher's clipboard plugin.
    ClipboardWatch { id: clipboardWatchService }
    // Music recognition (QS card `shazam`, IPC `island shazam`).
    Shazam { id: shazamService; events: eventsService }
    // Countdown timer: a finished one opens the module on the focused output.
    Countdown {
        id: countdownService
        onFinished: if (Config.data.timer.openOnFinish ?? true)
            islandRegistry.forOutput(compositorService.focusedOutput ?? "")?.showTimerDone()
    }
    Recorder { id: recorderService }
    Dictation { id: dictationService; keyboardLayout: keyboardLayoutService }
    KeyboardLayout { id: keyboardLayoutService }
    // Keyboard pill: layout / Caps Lock under the text caret (or pointer).
    Caret { id: caretService; compositor: compositorService; registry: islandRegistry }
    KeyboardIndicator { id: keyboardIndicatorService; keyboardLayout: keyboardLayoutService; caret: caretService }
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
    Stash { id: stashService; cfg: Config.data.stash; events: eventsService }
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

    LockScope { id: lockScope; registry: islandRegistry; keyboard: keyboardIndicatorService; theme: themeService; wallpaper: wallpaperService }
    // Session actions (lock / log out / sleep / restart / shut down).
    Session { id: sessionService; lock: lockScope; compositor: compositorService }

    CaptureScope {
        id: captureService
        recorder: recorderService
        theme: themeService
        compositor: compositorService
        events: eventsService
    }

    IslandRegistry { id: islandRegistry }

    // Status indicators (one ring in the drop right of the island) + feeds.
    Statuses { id: statusesService }
    StatusFeeds {
        statuses: statusesService
        events: eventsService
        countdown: countdownService
        transcribe: stashService.transcribe
        shazam: shazamService
        recorder: recorderService
        localSend: localSendService
        semantic: wallpaperService.semantic
        pacman: pacmanWatchService
        downloads: downloadWatchService
        dictation: dictationService
        wallpaper: wallpaperService
        capture: captureService
    }

    // Wallpapers (wallr): favourites/history, random, video pause.
    Wallpaper {
        id: wallpaperService
        compositor: compositorService
        battery: batteryService
        theme: themeService
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
        events: eventsService
        battery: batteryService
        caffeine: caffeineService
        charging: eventChargingService
        countdown: countdownService
        keyboard: keyboardIndicatorService
        shazam: shazamService
        statuses: statusesService
        network: eventNetworkService
        audioOutput: eventAudioOutputService
        batteryEvents: eventBatteryService
        displays: eventDisplaysService
        drives: eventDrivesService
        downloads: downloadWatchService
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
                privacy: privacyService
                events: eventsService
                caffeine: caffeineService
                clipboardWatch: clipboardWatchService
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
                countdown: countdownService
                shazam: shazamService
                statuses: statusesService
                session: sessionService
                keyboard: keyboardIndicatorService
            }

            KeyboardOverlay {
                targetScreen: modelData
                keyboard: keyboardIndicatorService
                theme: themeService
                lock: lockScope
                compositor: compositorService
            }

            RecordRegionOverlay {
                targetScreen: modelData
                recorder: recorderService
                theme: themeService
                lock: lockScope
            }

            Corners {
                targetScreen: modelData
                visible: !lockScope.locked
            }
        }
    }
}
