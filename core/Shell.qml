import QtQuick
import Quickshell
import "../config"
import "../services"
import "../compositor"
import "../modules/lock"

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
    Dictation { id: dictationService }

    // Recording is WM-agnostic: the facade delegates to the Recorder service.
    Compositor {
        id: compositorService
        recorder: recorderService
    }

    LockScope { id: lockScope }

    Variants {
        model: Quickshell.screens

        delegate: Scope {
            required property ShellScreen modelData

            Island {
                screen: modelData
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
                lock: lockScope
            }

            Corners {
                screen: modelData
                visible: !lockScope.locked
            }
        }
    }
}
