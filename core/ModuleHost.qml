import QtQuick
import "../modules/launcher"
import "../modules/notifications"
import "../modules/capture"
import "../modules/quicksettings"
import "../modules/dashboard"
import "../modules/dictation"
import "../modules/localsend"
import "../modules/osd"
import "../modules/player"

Item {
    id: root
    required property string moduleName
    required property var payload
    required property var services
    signal closeRequested

    // Shared-element slot of the CURRENTLY rendered module (TransitionLayer):
    // null until that module exists or when it declares no such slot.
    function sharedSlot(name: string, key: string): var {
        if (root.moduleName !== name || !host.item || typeof host.item.sharedSlot !== "function")
            return null;
        return host.item.sharedSlot(key);
    }

    // Content-fitted height the current module asks for (-1 = none; Island
    // then uses the config.modules size). Only the notification center sets it.
    readonly property real preferredHeight: host.item?.preferredHeight ?? -1

    Loader {
        id: host
        anchors.fill: parent
        sourceComponent: {
            if (root.moduleName === "launcher")
                return launcherComp;
            if (root.moduleName === "notifications")
                return notificationsComp;
            if (root.moduleName === "capture")
                return captureComp;
            if (root.moduleName === "quicksettings")
                return quickSettingsComp;
            if (root.moduleName === "dashboard")
                return dashboardComp;
            if (root.moduleName === "player")
                return playerComp;
            if (root.moduleName === "dictation")
                return dictationComp;
            if (root.moduleName === "localsend")
                return localSendComp;
            if (root.moduleName === "osd")
                return osdComp;
            if (root.moduleName === "recording-actions")
                return recordingActionsComp;
            if (root.moduleName === "hotspot-actions")
                return hotspotActionsComp;
            return null;
        }
    }

    Component {
        id: launcherComp
        LauncherModule { onCloseRequested: root.closeRequested() }
    }
    Component {
        id: notificationsComp
        NotificationsModule {
            payload: root.payload
            notificationsService: root.services.notifications
            cfg: root.services.config.notifications
            theme: root.services.theme
            onCloseRequested: root.closeRequested()
        }
    }
    Component {
        id: captureComp
        CaptureModule {
            onCloseRequested: root.closeRequested()
        }
    }
    Component {
        id: quickSettingsComp
        QuickSettingsModule {
            audio: root.services.audio
            players: root.services.players
            network: root.services.network
            bluetooth: root.services.bluetooth
            brightness: root.services.brightness
            notifications: root.services.notifications
            onCloseRequested: root.closeRequested()
        }
    }
    Component {
        id: dashboardComp
        DashboardModule {
            clock: root.services.clock
            battery: root.services.battery
            players: root.services.players
            systemUsage: root.services.systemUsage
            weather: root.services.weather
            sensors: root.services.sensors
            theme: root.services.theme
            dash: root.services.config.dashboard
            onCloseRequested: root.closeRequested()
        }
    }
    Component {
        id: playerComp
        PlayerModule {
            players: root.services.players
            theme: root.services.theme
            cfg: root.services.config.dashboard
            surfaceRadius: root.services.config.island.radius
            onCloseRequested: root.closeRequested()
        }
    }
    Component {
        id: dictationComp
        DictationModule {
            dictation: root.services.dictation
            onCloseRequested: root.closeRequested()
        }
    }
    Component {
        id: localSendComp
        LocalSendModule { onCloseRequested: root.closeRequested() }
    }
    Component {
        id: osdComp
        OsdModule {
            payload: root.payload
            onCloseRequested: root.closeRequested()
        }
    }
    Component {
        id: recordingActionsComp
        RecordingActionsModule {
            recorder: root.services.recorder
            theme: root.services.theme
            cfg: root.services.config.capture
            onCloseRequested: root.closeRequested()
        }
    }
    Component {
        id: hotspotActionsComp
        ActionButtonsModule {
            kind: "hotspot"
            recorder: root.services.recorder
            network: root.services.network
            theme: root.services.theme
            onCloseRequested: root.closeRequested()
        }
    }
}
