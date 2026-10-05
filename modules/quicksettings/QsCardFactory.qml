import QtQuick
import "./cards"

// Card id → content Component, bound to the services. Ids/footprints live
// in QsCatalog.js; this file only says what each card shows and does.
Item {
    id: root
    required property var services
    signal closeRequested
    signal openRequested(string name, var payload)

    readonly property var theme: root.services.theme
    readonly property var audio: root.services.audio
    readonly property var network: root.services.network
    readonly property var bluetooth: root.services.bluetooth
    readonly property var notifications: root.services.notifications
    readonly property var recorder: root.services.recorder

    function componentFor(id: string): Component {
        return ({
            wifi: wifiComp, bluetooth: btComp, hotspot: hotspotComp, dnd: dndComp, mic: micComp,
            volume: volumeComp, brightness: brightnessComp, media: mediaComp,
            record: recordComp, screenshot: screenshotComp
        })[id] ?? null;
    }

    Component {
        id: wifiComp
        ToggleCard {
            glyph: on ? "" : ""
            title: "Wi‑Fi"
            on: root.network?.wifiEnabled ?? false
            subtitle: !on ? "Выкл." : (root.network?.wifiConnected ? root.network.wifiSsid : "Не подключено")
            activate: () => root.network?.toggleWifi()
        }
    }
    Component {
        id: btComp
        ToggleCard {
            readonly property var devices: root.bluetooth?.connectedDevices ?? []
            glyph: !on ? "" : devices.length > 0 ? "" : ""
            title: "Bluetooth"
            on: root.bluetooth?.powered ?? false
            subtitle: !on ? "Выкл." : devices.length > 0 ? (devices[0].name ?? "Подключено") : "Вкл."
            activate: () => root.bluetooth?.toggle()
        }
    }
    Component {
        id: hotspotComp
        ToggleCard {
            glyph: on ? "" : ""
            title: "Точка доступа"
            accent: root.theme?.qsGreen ?? "#30D158"
            on: root.network?.hotspotEnabled ?? false
            subtitle: on ? (root.network?.hotspotName ?? "") : "Выкл."
            activate: () => root.network?.setHotspotEnabled(!on)
        }
    }
    Component {
        id: dndComp
        ToggleCard {
            glyph: ""
            title: "Не беспокоить"
            accent: root.theme?.qsIndigo ?? "#5E5CE6"
            on: root.notifications?.doNotDisturb ?? false
            subtitle: on ? "Вкл." : "Выкл."
            activate: () => {
                if (root.notifications)
                    root.notifications.doNotDisturb = !root.notifications.doNotDisturb;
            }
        }
    }
    Component {
        id: micComp
        ToggleCard {
            glyph: on ? "" : ""
            title: "Микрофон"
            accent: root.theme?.qsOrange ?? "#FF9F0A"
            on: !(root.audio?.sourceMuted ?? true)
            subtitle: on ? "Вкл." : "Выкл."
            activate: () => { root.audio?.quiet(); root.audio?.toggleSourceMute(); }
        }
    }
    Component {
        id: recordComp
        ToggleCard {
            glyph: on ? "" : ""
            title: "Запись экрана"
            accent: root.theme?.accentRed ?? "#E4483E"
            on: root.recorder?.recording ?? false
            subtitle: on ? (root.recorder?.elapsedText ?? "") : "Выкл."
            activate: () => {
                if (root.recorder?.recording)
                    root.recorder.stop();
                else
                    root.services.quickAction("record");
            }
        }
    }
    Component {
        id: screenshotComp
        ToggleCard {
            glyph: ""
            title: "Снимок экрана"
            subtitle: "Область"
            activate: () => root.services.quickAction("screenshot")
        }
    }
    Component {
        id: volumeComp
        SliderCard {
            readonly property bool muted: root.audio?.muted ?? false
            readonly property real max: root.audio?.maxVolume ?? 1
            title: "Громкость"
            value: muted ? 0 : (root.audio?.volume ?? 0) / max
            glyph: muted || value <= 0 ? "" : value < 0.5 ? "" : ""
            activate: () => { root.audio?.quiet(); root.audio?.toggleMute(); }
            // quiet(): no OSD for Quick Settings changes (core/OsdWatcher).
            onMoved: v => { root.audio?.quiet(); root.audio?.setVolume(v * max); }
        }
    }
    Component {
        id: brightnessComp
        SliderCard {
            title: "Яркость"
            value: root.services.brightness?.brightness ?? 0
            glyph: value < 0.5 ? "" : ""
            onMoved: v => { root.services.brightness?.quiet(); root.services.brightness?.setBrightness(v); }
        }
    }
    Component {
        id: mediaComp
        MediaCard {
            players: root.services.players
            activate: () => {
                if (hasPlayer)
                    root.openRequested("player", {});
            }
        }
    }
}
