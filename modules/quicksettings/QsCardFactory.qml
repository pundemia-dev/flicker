import QtQuick
import Quickshell
import "./cards"
import "./panels"
import "../../config"
import "../../services"
import "QsCatalog.js" as QsCatalog

// Card id → content Component, bound to the services. Ids/footprints live
// in QsCatalog.js; this file only says what each card shows and does.
Item {
    id: root
    required property var services
    signal closeRequested
    signal openRequested(string name, var payload)
    // A button inside a card opens a panel from itself (QsExpander.openPanel).
    signal expandRequested(Item source, string panel)

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
            record: recordComp, screenshot: screenshotComp, scanCode: scanCodeComp,
            localsend: localsendComp,
            slideshow: slideshowComp,
            lowPower: lowPowerComp,
            airplane: airplaneComp,
            caffeine: caffeineComp,
            nightLight: nightLightComp,
            vpn: vpnComp,
            shazam: shazamComp,
            timer: timerComp,
            calculator: calculatorComp,
            dictation: dictationComp,
            focus: focusComp
        })[id] ?? (root.stubs[id] ? stubComp : null);
    }

    // Expanded view of a card (QsExpander, long press); null = none.
    function panelFor(id: string): Component {
        return ({
            wifi: wifiPanelComp,
            bluetooth: btPanelComp,
            vpn: vpnPanelComp,
            nightLight: nightLightPanelComp,
            audio: audioPanelComp,
            tray: trayMenuComp
        })[id] ?? null;
    }
    // A system tray item's menu (QsTray: right click / long press).
    Component {
        id: trayMenuComp
        TrayMenuPanel {
            services: root.services
            onCloseRequested: root.closeRequested()
            cfg: root.services.config.quicksettings
            theme: root.theme
            frost: root.services.frost ?? null
        }
    }
    Component {
        id: wifiPanelComp
        WifiPanel {
            services: root.services
            onCloseRequested: root.closeRequested()
            cfg: root.services.config.quicksettings
            theme: root.theme
            frost: root.services.frost ?? null
        }
    }
    Component {
        id: vpnPanelComp
        VpnPanel {
            services: root.services
            onCloseRequested: root.closeRequested()
            cfg: root.services.config.quicksettings
            theme: root.theme
            frost: root.services.frost ?? null
        }
    }
    Component {
        id: nightLightPanelComp
        NightLightPanel {
            services: root.services
            onCloseRequested: root.closeRequested()
            cfg: root.services.config.quicksettings
            theme: root.theme
            frost: root.services.frost ?? null
        }
    }
    // Opened by the media card's output button, not a long press (no
    // "audio" card).
    Component {
        id: audioPanelComp
        AudioPanel {
            services: root.services
            onCloseRequested: root.closeRequested()
            cfg: root.services.config.quicksettings
            theme: root.theme
            frost: root.services.frost ?? null
        }
    }
    Component {
        id: btPanelComp
        BluetoothPanel {
            services: root.services
            cfg: root.services.config.quicksettings
            theme: root.theme
            frost: root.services.frost ?? null
        }
    }

    // Placeholder cards (no backend yet): toggles flip a session-only local
    // state so the tap reads, actions do nothing. Replace with a real
    // Component above when a card gets its service.
    readonly property var stubs: ({
        magnifier: { toggle: false },
        voiceMemos: { toggle: false, accent: "accentRed" },
        notes: { toggle: false },
        translate: { toggle: false, status: "English → Russian" },
        cellular: { toggle: true, accent: "qsGreen" },
        stopwatch: { toggle: false },
        mirroring: { toggle: false }
    })

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
    // Focus: the island stays Minimal everywhere, as under a fullscreen
    // window (ControlCenter.focusMode → Island.fsActive).
    Component {
        id: focusComp
        ButtonCard {
            readonly property var cc: root.services.controlCenter
            glyph: QsCatalog.glyphOf("focus")
            title: I18n.tr("Focus")
            accent: root.theme?.qsIndigo ?? "#5E5CE6"
            on: cc?.focusMode ?? false
            activate: () => {
                if (cc)
                    cc.focusMode = !cc.focusMode;
            }
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
            status: on ? I18n.tr("Every %1").arg(I18n.tr("%1 min").arg(Math.max(1, Math.round((root.services.wallpaper?.cfg.slideshowIntervalSec ?? 900) / 60)))) : I18n.tr("Off")
            activate: () => show?.toggle(null)
        }
    }
    // Low Power Mode (services/PowerMode): the system power-saver profile;
    // no power-profiles daemon → "Unavailable", the tap only re-probes.
    Component {
        id: lowPowerComp
        ButtonCard {
            readonly property var mode: root.services.powerMode ?? null
            glyph: QsCatalog.glyphOf("lowPower")
            title: I18n.tr(QsCatalog.titleOf("lowPower"))
            accent: root.theme?.qsYellow ?? "#FFCC00"
            on: mode?.active ?? false
            status: !(mode?.available ?? false) ? I18n.tr("Unavailable") : on ? I18n.tr("On") : I18n.tr("Off")
            activate: () => mode?.toggle()
        }
    }
    // Airplane Mode (services/Airplane): every radio rfkill-blocked; off
    // restores what was on before. No rfkill devices → "Unavailable".
    Component {
        id: airplaneComp
        ButtonCard {
            readonly property var mode: root.services.airplane ?? null
            glyph: QsCatalog.glyphOf("airplane")
            title: I18n.tr(QsCatalog.titleOf("airplane"))
            accent: root.theme?.qsOrange ?? "#FF9F0A"
            on: mode?.active ?? false
            status: !(mode?.available ?? false) ? I18n.tr("Unavailable") : on ? I18n.tr("On") : I18n.tr("Off")
            activate: () => mode?.toggle()
        }
    }
    // Caffeine (services/Caffeine): the idle chain held (no dim / lock /
    // sleep); a tap keeps it on for caffeine.minutes (0 = until off).
    // Status = time left / On, or what else keeps the screen awake now.
    Component {
        id: caffeineComp
        ButtonCard {
            readonly property var caffeine: root.services.caffeine ?? null
            readonly property var others: (root.services.idle?.holders ?? []).filter(h => h.kind !== "caffeine")
            glyph: QsCatalog.glyphOf("caffeine")
            title: I18n.tr(QsCatalog.titleOf("caffeine"))
            accent: root.theme?.coffee ?? "#C8915A"
            on: caffeine?.active ?? false
            status: !on && others.length > 0 ? I18n.tr("Held by %1").arg(others[0].label) : (caffeine?.status ?? I18n.tr("Off"))
            activate: () => caffeine?.toggle()
        }
    }
    // Night Light (services/NightLight): a tap against the schedule holds
    // until its next turn; status = until / from when. Long press = the
    // panel (warmth, today's schedule).
    Component {
        id: nightLightComp
        ButtonCard {
            readonly property var nl: root.services.nightLight ?? null
            glyph: QsCatalog.glyphOf("nightLight")
            title: I18n.tr(QsCatalog.titleOf("nightLight"))
            accent: root.theme?.qsOrange ?? "#FF9F0A"
            on: nl?.active ?? false
            status: nl?.status ?? I18n.tr("Unavailable")
            activate: () => nl?.toggle()
        }
    }
    // VPN (services/Vpn): sing-box on / off; status = the node, or the
    // transition. Long press = the panel (nodes, ping, subscription).
    Component {
        id: vpnComp
        ButtonCard {
            readonly property var vpn: root.services.vpn ?? null
            readonly property string st: vpn?.status ?? "inactive"
            glyph: on ? "\ued58" : "\ueb24"
            title: "VPN"
            on: vpn?.on ?? false
            status: {
                switch (st) {
                case "unavailable":
                    return I18n.tr("Not installed");
                case "connecting":
                    return I18n.tr("Connecting…");
                case "disconnecting":
                    return I18n.tr("Disconnecting…");
                case "failed":
                    return I18n.tr("Failed");
                case "offline":
                    return I18n.tr("No connection");
                case "blocked":
                    return I18n.tr("Traffic blocked");
                case "active":
                    return vpn.profile || I18n.tr("Connected");
                }
                return I18n.tr("Off");
            }
            activate: () => vpn?.toggle()
        }
    }
    // Music recognition (services/Shazam): lit while listening, tap =
    // listen / cancel; status = the outcome for a while, else the last match.
    Component {
        id: shazamComp
        ButtonCard {
            readonly property var shazam: root.services.shazam ?? null
            readonly property var last: shazam?.result ?? null
            glyph: QsCatalog.glyphOf("shazam")
            title: I18n.tr(QsCatalog.titleOf("shazam"))
            accent: root.theme?.shazam ?? "#0088FF"
            on: shazam?.listening ?? false
            status: {
                switch (shazam?.phase ?? "idle") {
                case "listening":
                    return shazam.source === "mic" ? I18n.tr("Listening to the mic…") : I18n.tr("Listening…");
                case "none":
                    return I18n.tr("No match");
                case "error":
                    return I18n.tr("Failed");
                }
                return last ? (last.artist ? `${last.title} — ${last.artist}` : last.title) : I18n.tr("Tap to listen");
            }
            activate: () => shazam?.toggle()
        }
    }
    // Timer (services/Countdown): lit while it runs, status = time left;
    // a tap opens the timer module (setup / countdown).
    Component {
        id: timerComp
        ButtonCard {
            readonly property var countdown: root.services.countdown ?? null
            glyph: "\uef93"
            title: I18n.tr("Timer")
            accent: root.theme?.timerAccent ?? "#FF9F0A"
            on: countdown?.active ?? false
            status: on ? countdown.remainingText : I18n.tr("%1 min").arg(countdown?.setupMinutes ?? 0)
            activate: () => root.openRequested("timer", {})
        }
    }
    // Dictation (services/Dictation): lit while a typing session runs; a
    // tap starts one and closes Quick Settings (the text goes to the focused
    // window), a tap while it runs stops it. A prompter session owns the
    // backend: the card shows it and ignores taps (Dictation.toggle()).
    Component {
        id: dictationComp
        ButtonCard {
            readonly property var dictation: root.services.dictation ?? null
            readonly property bool mine: (dictation?.sink ?? "type") === "type"
            glyph: QsCatalog.glyphOf("dictation")
            title: I18n.tr(QsCatalog.titleOf("dictation"))
            accent: root.theme?.qsBlue ?? "#0A84FF"
            on: dictation?.active ?? false
            status: {
                if (!on)
                    return I18n.tr("Off");
                if (!mine)
                    return I18n.tr("Prompter");
                switch (dictation.phase) {
                case "switching":
                    return I18n.tr("Starting…");
                case "finalizing":
                case "refining":
                    return I18n.tr("Finishing…");
                }
                return I18n.tr("Listening…");
            }
            activate: () => {
                if (!dictation || (dictation.active && !mine))
                    return;
                const starting = !dictation.active;
                dictation.toggle();
                if (starting)
                    root.closeRequested();
            }
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
        id: scanCodeComp
        ButtonCard {
            glyph: QsCatalog.glyphOf("scanCode")
            title: I18n.tr(QsCatalog.titleOf("scanCode"))
            toggle: false
            activate: () => root.services.quickAction("scan")
        }
    }
    Component {
        id: localsendComp
        ButtonCard {
            glyph: QsCatalog.glyphOf("localsend")
            title: I18n.tr(QsCatalog.titleOf("localsend"))
            toggle: false
            activate: () => root.services.openStash?.("")
        }
    }
    // Calculator: whatever the user has — cfg.calculator (desktop ids /
    // names, first installed wins), else the first .desktop entry in the
    // freedesktop "Calculator" category. Tap = focus its window or start it.
    AppActivator {
        id: activator
        launchPrefix: Config.data.launcher?.apps?.launchPrefix ?? []
    }
    Component {
        id: calculatorComp
        ButtonCard {
            readonly property var app: {
                const apps = DesktopEntries.applications?.values ?? [];
                for (const name of root.services.config.quicksettings.calculator ?? []) {
                    const hit = activator.desktopEntryFor(activator.expand([name]));
                    if (hit)
                        return hit;
                }
                return apps.find(a => (a.categories ?? []).includes("Calculator")) ?? null;
            }
            glyph: QsCatalog.glyphOf("calculator")
            title: I18n.tr(QsCatalog.titleOf("calculator"))
            toggle: false
            statusShown: !app
            status: I18n.tr("Not installed")
            activate: () => {
                if (!app)
                    return;
                if (!activator.activate([app.id]))
                    activator.launch([app.id]);
                root.closeRequested();
            }
        }
    }
    Component {
        id: stubComp
        ButtonCard {
            id: stub
            readonly property string cardId: card?.cardId ?? ""
            readonly property var spec: root.stubs[cardId] ?? {}
            glyph: QsCatalog.glyphOf(cardId)
            title: I18n.tr(QsCatalog.titleOf(cardId))
            toggle: spec.toggle ?? false
            statusShown: toggle || !!spec.status
            status: spec.status ? I18n.tr(spec.status) : (on ? I18n.tr("On") : I18n.tr("Off"))
            accent: (spec.accent ? root.theme?.[spec.accent] : null) ?? root.theme?.qsBlue ?? "#0A84FF"
            activate: () => {
                if (stub.toggle)
                    stub.on = !stub.on;
            }
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
            openOutput: src => root.expandRequested(src, "audio")
            activate: () => {
                if (hasPlayer && !hasProgress)
                    root.openRequested("player", {});
            }
        }
    }
}
