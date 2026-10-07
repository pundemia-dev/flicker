import QtQuick
import "./cards"
import "../../config"

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
            record: recordComp, screenshot: screenshotComp, slideshow: slideshowComp
        })[id] ?? null;
    }

    Component {
        id: wifiComp
        ButtonCard {
            glyph: on ? "" : ""
            title: "Wi‑Fi"
            on: root.network?.wifiEnabled ?? false
            status: !on ? I18n.tr("Off") : (root.network?.wifiConnected ? root.network.wifiSsid : I18n.tr("Not connected"))
            activate: () => root.network?.toggleWifi()
        }
    }
    Component {
        id: btComp
        ButtonCard {
            readonly property var devices: root.bluetooth?.connectedDevices ?? []
            glyph: !on ? "" : devices.length > 0 ? "" : ""
            title: "Bluetooth"
            on: root.bluetooth?.powered ?? false
            status: !on ? I18n.tr("Off") : devices.length > 0 ? (devices[0].name ?? I18n.tr("Connected")) : I18n.tr("On")
            activate: () => root.bluetooth?.toggle()
        }
    }
    Component {
        id: hotspotComp
        ButtonCard {
            glyph: on ? "" : ""
            title: I18n.tr("Hotspot")
            accent: root.theme?.qsGreen ?? "#30D158"
            on: root.network?.hotspotEnabled ?? false
            status: on ? (root.network?.hotspotName ?? "") : I18n.tr("Off")
            activate: () => root.network?.setHotspotEnabled(!on)
        }
    }
    Component {
        id: dndComp
        ButtonCard {
            glyph: ""
            title: I18n.tr("Do Not Disturb")
            accent: root.theme?.qsIndigo ?? "#5E5CE6"
            on: root.notifications?.doNotDisturb ?? false
            activate: () => {
                if (root.notifications)
                    root.notifications.doNotDisturb = !root.notifications.doNotDisturb;
            }
        }
    }
    Component {
        id: micComp
        ButtonCard {
            glyph: on ? "" : ""
            title: I18n.tr("Microphone")
            accent: root.theme?.qsOrange ?? "#FF9F0A"
            on: !(root.audio?.sourceMuted ?? true)
            activate: () => { root.audio?.quiet(); root.audio?.toggleSourceMute(); }
        }
    }
    Component {
        id: recordComp
        ButtonCard {
            glyph: on ? "" : ""
            title: I18n.tr("Screen Recording")
            accent: root.theme?.accentRed ?? "#E4483E"
            on: root.recorder?.recording ?? false
            status: on ? (root.recorder?.elapsedText ?? "") : I18n.tr("Off")
            activate: () => {
                if (root.recorder?.recording)
                    root.recorder.stop();
                else
                    root.services.quickAction("record");
            }
        }
    }
    // Wallpaper slideshow (services/WallpaperSlideshow) over all wallpapers;
    // Ctrl+S in the launcher carousel starts it over a filtered view.
    Component {
        id: slideshowComp
        ButtonCard {
            readonly property var show: root.services.wallpaper?.slideshow ?? null
            glyph: "\uebc9"
            title: I18n.tr("Slideshow")
            accent: root.theme?.qsGreen ?? "#38C65A"
            on: show?.active ?? false
            status: on ? I18n.tr("Every %1").arg(I18n.tr("%1 min").arg(Math.max(1, Math.round((root.services.config?.launcher?.wallpapers?.slideshowIntervalSec ?? 900) / 60)))) : I18n.tr("Off")
            activate: () => show?.toggle(null)
        }
    }
    Component {
        id: screenshotComp
        ButtonCard {
            glyph: ""
            title: I18n.tr("Screenshot")
            toggle: false
            activate: () => root.services.quickAction("screenshot")
        }
    }
    Component {
        id: volumeComp
        SliderCard {
            readonly property real max: root.audio?.maxVolume ?? 1
            muted: root.audio?.muted ?? false
            title: I18n.tr("Volume")
            haptics: root.services.haptics
            value: muted ? 0 : (root.audio?.volume ?? 0) / max
            volume: true
            iconColor: root.theme?.qsVolumeIcon ?? "#00BFE9"
            levelScale: max
            activate: () => { root.audio?.quiet(); root.audio?.toggleMute(); }
            // quiet(): no OSD for Quick Settings changes (core/OsdWatcher).
            onMoved: v => { root.audio?.quiet(); root.audio?.setVolume(v * max); }
        }
    }
    Component {
        id: brightnessComp
        SliderCard {
            title: I18n.tr("Brightness")
            haptics: root.services.haptics
            iconColor: root.theme?.qsBrightnessIcon ?? "#FFCB01"
            value: root.services.brightness?.brightness ?? 0
            glyph: value < 0.5 ? "\uD800\uDD07" : "\uD800\uDD08"
            onMoved: v => { root.services.brightness?.quiet(); root.services.brightness?.setBrightness(v); }
        }
    }
    Component {
        id: mediaComp
        MediaCard {
            players: root.services.players
            audio: root.audio
            haptics: root.services.haptics
            activate: () => {
                if (hasPlayer && !hasProgress)
                    root.openRequested("player", {});
            }
        }
    }
}
