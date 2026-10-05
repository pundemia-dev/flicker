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
    SystemUsage { id: systemUsageService }
    Sensors { id: sensorsService }
    Weather { id: weatherService }

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

    IslandIpc {
        registry: islandRegistry
        compositor: compositorService
        audio: audioService
        brightness: brightnessService
        players: playersService
        lock: lockScope
        capture: captureService
        recorder: recorderService
    }

    OsdWatcher {
        registry: islandRegistry
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
            }

            Corners {
                targetScreen: modelData
                visible: !lockScope.locked
            }
        }
    }
}
