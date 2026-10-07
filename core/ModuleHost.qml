import QtQuick
import "../modules/launcher"
import "../modules/notifications"
import "../modules/capture"
import "../modules/quicksettings"
import "../modules/dashboard"
import "../modules/dictation"
import "../modules/stash"
import "../modules/osd"
import "../modules/player"
import "../modules/polkit"
import "../modules/prompter"

Item {
    id: root
    required property string moduleName
    required property var payload
    required property var services
    signal closeRequested
    // A module switching to another module/view (stash tray → picker, drop
    // chooser → tray): Island.openModule, so the swap + resize replay.
    signal openRequested(string name, var payload)

    // Shared-element slot of the CURRENTLY rendered module (TransitionLayer):
    // null until that module exists or when it declares no such slot.
    function sharedSlot(name: string, key: string): var {
        if (root.moduleName !== name || !host.item || typeof host.item.sharedSlot !== "function")
            return null;
        return host.item.sharedSlot(key);
    }

    // Content-fitted size the current module asks for (-1 = none; Island
    // then uses the config.modules size). The notification center sets the
    // height, the launcher both.
    readonly property real preferredWidth: host.item?.preferredWidth ?? -1
    readonly property real preferredHeight: host.item?.preferredHeight ?? -1
    // Frost knockouts (components/Knockout.js) in module = island coords.
    readonly property var knockouts: host.item?.knockouts ?? []
    // A file drag over the module's own drop targets (stash drop chooser):
    // the island's drop area loses containsDrag under them.
    readonly property bool dragActive: host.item?.dragActive ?? false

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
            if (root.moduleName === "stash")
                return stashComp;
            if (root.moduleName === "stash-drop")
                return stashDropComp;
            if (root.moduleName === "osd")
                return osdComp;
            if (root.moduleName === "recording-actions")
                return recordingActionsComp;
            if (root.moduleName === "hotspot-actions")
                return hotspotActionsComp;
            if (root.moduleName === "polkit")
                return polkitComp;
            if (root.moduleName === "prompter")
                return prompterComp;
            return null;
        }
    }

    Component {
        id: launcherComp
        LauncherModule {
            payload: root.payload
            theme: root.services.theme
            cfg: root.services.config.launcher
            host: root.services.launcherHost ?? null
            onCloseRequested: root.closeRequested()
        }
    }
    Component {
        id: notificationsComp
        NotificationsModule {
            payload: root.payload
            notificationsService: root.services.notifications
            cfg: root.services.config.notifications
            theme: root.services.theme
            frost: root.services.frost ?? null
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
            services: root.services
            onCloseRequested: root.closeRequested()
            onOpenRequested: (name, payload) => root.openRequested(name, payload)
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
            haptics: root.services.haptics
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
        id: stashComp
        StashModule {
            payload: root.payload
            stash: root.services.stash
            localSend: root.services.localSend
            cfg: root.services.config.stash
            theme: root.services.theme
            surfaceRadius: root.services.config.island.radius
            onCloseRequested: root.closeRequested()
            onOpenRequested: (name, payload) => root.openRequested(name, payload)
        }
    }
    Component {
        id: stashDropComp
        StashDropModule {
            payload: root.payload
            stash: root.services.stash
            localSend: root.services.localSend
            cfg: root.services.config.stash
            theme: root.services.theme
            surfaceRadius: root.services.config.island.radius
            onCloseRequested: root.closeRequested()
            onOpenRequested: (name, payload) => root.openRequested(name, payload)
        }
    }
    Component {
        id: osdComp
        OsdModule {
            payload: root.payload
            theme: root.services.theme
            audio: root.services.audio
            brightness: root.services.brightness
            onCloseRequested: root.closeRequested()
        }
    }
    Component {
        id: polkitComp
        PolkitModule {
            polkit: root.services.polkit
            theme: root.services.theme
            cfg: root.services.config.polkit
            onCloseRequested: root.closeRequested()
        }
    }
    Component {
        id: prompterComp
        PrompterModule {
            prompter: root.services.prompter
            theme: root.services.theme
            cfg: root.services.config.prompter
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
