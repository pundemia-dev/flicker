.pragma library
.import "../launcher/plugins/wallpapers/WallSettingsList.js" as Wall

// What the settings window shows: module BEHAVIOUR only (user decision —
// no paddings / radii / springs, those stay in config.json). Strings are
// English I18n keys, translated at the display site.
//
// SIDEBAR = clusters of sections (gaps between clusters, iOS style).
// Section { id, title, glyph (tabler), tint (Theme colour name), groups }.
// Group { title?, footer?, rows }; `footerFrom` = a live footer
// (SettingsWindow.footerOf: an error in red instead of the footer).
// Row { key (dotted config path), label, kind, ... }:
//   bool                  switch
//   choice  options       [{ value, label }]; `segments` = inline segmented
//                         control instead of the pull-down menu
//   number  min max step  raw config units; shown as value / scale with
//           scale suffix  `decimals` places + suffix; `slider` = a slider
//           decimals      under the label instead of the stepper;
//           zeroLabel     `zeroLabel` = shown instead of 0 ("Off");
//           time          `time` = minutes after midnight shown as HH:MM
//   text                  inline field; `array` = string list joined by
//                         spaces (argv / paths)
//   set     options       multi-select drill-down; the config holds the
//                         checked values (`invert`: the unchecked ones);
//                         `optionsFrom` works here too
//   page    page          drill-down to { title, groups }; `detail` =
//                         grey text before the chevron, `muted` = grey label
//   action  action        tappable blue text (SettingsWindow.act());
//                         `destructive` = red, `confirm` = label of a
//                         second tap that has to follow (3 s), `detail`
//                         = grey text at the right (SettingsWindow.detailOf)
//   info    options       read-only value (label of the current value)
// text rows: `wide` = the field on its own line under the label,
// `placeholder` = shown while empty, `allowEmpty` = emptying it stores ""
// (else the stored value comes back).
// Group `generate` = rows built from live data (SettingsWindow.groupsOf);
// its static `rows` stay empty (search skips it).
// options / store: `optionsFrom` = live options (SettingsWindow.optionsOf).
// Any row may carry `footer`-free `keywords` (search) and `glyph` + `tint`
// (icon tile). store "wallpaper" = launcher.wallpapers via the wallpaper
// service (the carousel's overrides, so both panels show the same values);
// store "vpn" = the VPN service's live state (its setters act on change),
// "vpnRule" = a field of one routing rule (SettingsVpn.js), "display" = an
// output's setting (SettingsDisplays.js). Group `widget` = a custom control
// above the rows (SettingsGroup: "displays" = the arrangement).
// dependsOn (row or group): the row dims and takes no input unless the
// condition holds (iOS: rows under an off master switch). "key" = truthy,
// "!key" = falsy, "key=value" = equal as text; an array = all of them;
// "vpn:key" reads the VPN service instead of the config. On a group it
// covers every row but the master itself (the row with that key) and the
// rows of its drill-down pages.

const S = 1000; // ms → s

function opts(list) {
    return list.map(v => typeof v === "object" ? v : { value: v, label: String(v) });
}

// Auto-Lock stage rows of one power source (idle.ac / idle.battery).
function IDLE_ROWS(src) {
    const m = { min: 0, max: 7200, step: 60, scale: 60, suffix: " min", zeroLabel: "Never" };
    return [
        Object.assign({ key: `idle.${src}.dimSec`, label: "Dim screen after", keywords: "idle" }, m, { kind: "number", step: 30, decimals: 1 }),
        Object.assign({ key: `idle.${src}.lockSec`, label: "Lock after", keywords: "idle auto-lock" }, m, { kind: "number" }),
        Object.assign({ key: `idle.${src}.screenOffSec`, label: "Turn screen off after", keywords: "idle dpms" }, m, { kind: "number" }),
        Object.assign({ key: `idle.${src}.sleepSec`, label: "Sleep after", keywords: "idle suspend" }, m, { kind: "number", step: 300 })
    ];
}

const LANGS = [{ value: "auto", label: "Automatic" }, { value: "en", label: "English" }, { value: "ru", label: "Russian" }];

// Carousel settings panel pages → groups (same rows, same store).
function wallGroups() {
    return Wall.PAGES.map(p => ({
        title: p.title,
        rows: p.rows.filter(r => r.kind === "bool" || r.kind === "choice")
            .map(r => Object.assign({}, r, { store: "wallpaper" }))
    }));
}

const SIDEBAR = [
    [
        {
            id: "general", title: "General", glyph: "", tint: "settingsGrey",
            groups: [
                { rows: [
                    { key: "i18n.language", label: "Language", kind: "choice", options: LANGS, keywords: "locale translation" }
                ] },
                { title: "Effects", footer: "Turns off every compositor blur behind the island and its modules.", rows: [
                    { key: "effects.disableBlur", label: "Disable blur", kind: "bool" },
                    { key: "effects.frost", label: "Frosted modules", kind: "bool", keywords: "glass blur" },
                    { key: "effects.frostModules", label: "Frosted", kind: "set", dependsOn: "effects.frost", options: [
                        { value: "quicksettings", label: "Quick Settings" },
                        { value: "notifications:center", label: "Notification Center" },
                        { value: "prompter", label: "Teleprompter" }
                    ] }
                ] }
            ]
        }
    ],
    [
        {
            id: "island", title: "Island", glyph: "", tint: "qsIndigo",
            groups: [
                { title: "Minimal", footer: "How long the island stays expanded before it shrinks back to the strip.", rows: [
                    { key: "timings.minimalIdleMs", label: "Collapse after", kind: "number", min: 1000, max: 15000, step: 500, scale: S, decimals: 1, suffix: " s" },
                    { key: "timings.moduleIdleFromMinimalMs", label: "Close module after", kind: "number", min: 1000, max: 15000, step: 500, scale: S, decimals: 1, suffix: " s" }
                ] },
                { title: "Indicators", footer: "A new indicator briefly unfolds the bar while the island is minimal.", rows: [
                    { key: "indicators.peekEnabled", label: "Peek on new indicator", kind: "bool" },
                    { key: "indicators.peekShowMs", dependsOn: "indicators.peekEnabled", label: "Peek for", kind: "number", min: 1000, max: 10000, step: 500, scale: S, decimals: 1, suffix: " s" },
                    { key: "indicators.peekIgnore", label: "Peeking indicators", kind: "set", dependsOn: "indicators.peekEnabled", invert: true, options: [
                        { value: "music", label: "Music" }, { value: "timer", label: "Timer" },
                        { value: "privacy", label: "Microphone / camera" }, { value: "dictation", label: "Dictation" },
                        { value: "event", label: "Events" }
                    ] },
                    { key: "indicators.musicTimerRing", label: "Timer ring around the cover", kind: "bool" }
                ] },
                { title: "Gestures", footer: "How far to drag before a gesture opens its module.", rows: [
                    { key: "gestures.sideDragThreshold", label: "Quick Settings / Notifications", kind: "number", min: 10, max: 120, step: 2, suffix: " px" },
                    { key: "gestures.dashboardDragThreshold", label: "Dashboard", kind: "number", min: 10, max: 120, step: 2, suffix: " px" }
                ] }
            ]
        },
        {
            id: "events", title: "Events", glyph: "", tint: "qsOrange",
            groups: [
                { footer: "Short messages in the bar: one at a time, queued ones show for a shorter time.", dependsOn: "events.enabled", rows: [
                    { key: "events.enabled", label: "Events", kind: "bool" },
                    { key: "events.showMs", label: "Show for", kind: "number", min: 1000, max: 15000, step: 500, scale: S, decimals: 1, suffix: " s" },
                    { key: "events.showQueuedMs", label: "Show queued for", kind: "number", min: 1000, max: 15000, step: 500, scale: S, decimals: 1, suffix: " s" }
                ] },
                { title: "Sources", dependsOn: "events.enabled", rows: [
                    { key: "events.charging", label: "Charger", kind: "bool" },
                    { key: "events.batteryFull", label: "Battery full", kind: "bool" },
                    { key: "events.batteryCritical", label: "Battery critical", kind: "bool" },
                    { key: "events.bluetooth", label: "Bluetooth devices", kind: "bool" },
                    { key: "events.wifi", label: "Wi-Fi", kind: "bool" },
                    { key: "events.audioOutput", label: "Audio output", kind: "bool" },
                    { key: "events.displays", label: "Displays", kind: "bool" },
                    { key: "events.drives", label: "Drives", kind: "bool" },
                    { key: "events.caffeine", label: "Caffeine", kind: "bool" },
                    { key: "events.nightLight", label: "Night Light", kind: "bool" },
                    { key: "events.shazam", label: "Shazam", kind: "bool" },
                    { key: "events.transcribe", label: "Transcription", kind: "bool" },
                    { key: "events.pacman", label: "Package manager", kind: "bool" },
                    { key: "events.download", label: "Downloads", kind: "bool" },
                    { key: "events.updates", label: "Updates", kind: "bool" }
                ] },
                { footer: "Updates are announced only right after boot, not on a shell restart. 0 = always.", dependsOn: ["events.enabled", "events.updates"], rows: [
                    { key: "events.updatesMaxUptimeSec", label: "Updates: boot window", kind: "number", min: 0, max: 900, step: 30, suffix: " s" }
                ] }
            ]
        },
        {
            id: "status", title: "Status", glyph: "降", tint: "settingsTeal",
            groups: [
                { footer: "Progress rings in the drop right of the island.", rows: [
                    { key: "status.enabled", label: "Status drop", kind: "bool" }
                ] },
                { title: "Show progress of", dependsOn: "status.enabled", rows: [
                    { key: "status.timer", label: "Timer", kind: "bool" },
                    { key: "status.recordSaving", label: "Saving a recording", kind: "bool" },
                    { key: "status.transcribe", label: "Transcription", kind: "bool" },
                    { key: "status.shazam", label: "Shazam", kind: "bool" },
                    { key: "status.localSend", label: "LocalSend", kind: "bool" },
                    { key: "status.lens", label: "Google Lens upload", kind: "bool" },
                    { key: "status.pacman", label: "Package manager", kind: "bool" },
                    { key: "status.download", label: "Downloads", kind: "bool" },
                    { key: "status.modelDownload", label: "Model downloads", kind: "bool" },
                    { key: "status.refineWarmup", label: "Dictation model loading", kind: "bool" },
                    { key: "status.wallpaperWarmup", label: "Wallpaper thumbnails", kind: "bool" },
                    { key: "status.wallpaperDupes", label: "Wallpaper duplicates scan", kind: "bool" }
                ] }
            ]
        }
    ],
    [
        {
            id: "notifications", title: "Notifications", glyph: "", tint: "accentRed",
            groups: [
                { footer: "Low-urgency notifications go straight to the Notification Center.", rows: [
                    { key: "notifications.onlyUrgentToast", label: "Hide low-urgency toasts", kind: "bool" },
                    { key: "notifications.flowMaxActions", label: "Action buttons", kind: "number", min: 0, max: 6, step: 1 },
                    { key: "notifications.codeCopy", label: "Copy button for codes", kind: "bool", keywords: "2fa otp one-time login verification" },
                    { key: "notifications.dedupe", label: "Merge repeats", kind: "bool", keywords: "duplicates dedupe spam" }
                ] },
                { title: "Toast duration", footer: "Critical at 0 stays until dismissed; the queue waits behind it. With the app's timeout, an app that sets one decides instead.", rows: [
                    { key: "notifications.flowShowMs", label: "Normal", kind: "number", min: 1000, max: 20000, step: 500, scale: S, decimals: 1, suffix: " s", keywords: "timeout" },
                    { key: "notifications.flowShowLowMs", label: "Low urgency", kind: "number", min: 1000, max: 20000, step: 500, scale: S, decimals: 1, suffix: " s", dependsOn: "!notifications.onlyUrgentToast", keywords: "timeout" },
                    { key: "notifications.flowShowCriticalMs", label: "Critical", kind: "number", min: 0, max: 60000, step: 1000, scale: S, suffix: " s", zeroLabel: "Until dismissed", keywords: "timeout" },
                    { key: "notifications.flowShowQueuedMs", label: "With more queued", kind: "number", min: 1000, max: 20000, step: 500, scale: S, decimals: 1, suffix: " s", keywords: "timeout" },
                    { key: "notifications.appTimeout", label: "Use the app's timeout", kind: "bool", keywords: "expire timeout" }
                ] },
                { title: "Do Not Disturb", footer: "Notifications still go to the Notification Center, just without a toast or a sound.", rows: [
                    { store: "notifications", key: "doNotDisturb", label: "Do Not Disturb", kind: "bool", keywords: "dnd silence" },
                    { key: "notifications.dndWhileSharing", label: "While sharing the screen", kind: "bool", keywords: "dnd screencast recording" },
                    { key: "notifications.dndAllowCritical", label: "Let critical through", kind: "bool", keywords: "dnd urgent" }
                ] },
                { title: "Privacy", footer: "Hidden: a toast shows only the app name until you pull it open. Sharing = a screencast or a screen recording.", rows: [
                    { key: "notifications.privacy", label: "Toast text", kind: "choice", keywords: "hide private sharing", options: [
                        { value: "off", label: "Shown" }, { value: "sharing", label: "Hidden while sharing" }, { value: "always", label: "Hidden" }
                    ] }
                ] },
                { title: "Displays", footer: "Without a connected display to show on, toasts go to the focused one. The Notification Center opens on any.", rows: [
                    { key: "notifications.screens", label: "Show toasts on", kind: "choice", keywords: "monitor output screen", options: [
                        { value: "all", label: "All displays" }, { value: "focused", label: "Focused display" },
                        { value: "only", label: "Only selected" }, { value: "except", label: "All but selected" }
                    ] },
                    { key: "notifications.screenList", label: "Selected", kind: "set", optionsFrom: "screens", keywords: "monitor output screen",
                        dependsOn: ["!notifications.screens=all", "!notifications.screens=focused"] }
                ] },
                { title: "Rules", footer: "Mute an app from a notification: pull it open, then Mute.", generate: "notifRules", rows: [] },
                { title: "Sound", footer: "Silent while Do Not Disturb is on (but critical ones with Let critical through, and rules that pass it), muted by a rule, and when the app asks for no sound.", rows: [
                    { key: "notifications.sound", label: "Play a sound", kind: "bool" },
                    { key: "notifications.soundLowUrgency", dependsOn: "notifications.sound", label: "For low-urgency too", kind: "bool" },
                    { key: "notifications.soundFile", dependsOn: "notifications.sound", label: "Sound file", kind: "text", wide: true, placeholder: "/usr/share/sounds/…" }
                ] },
                { title: "Fullscreen ticker", footer: "Notifications while a window is fullscreen scroll by in the strip.", rows: [
                    { key: "notifications.tickerSpeed", label: "Scroll speed", kind: "number", min: 20, max: 200, step: 10, suffix: " px/s" },
                    { key: "notifications.tickerHoldMs", label: "Hold before scrolling", kind: "number", min: 0, max: 5000, step: 100, scale: S, decimals: 1, suffix: " s" }
                ] },
                { title: "Notification Center", rows: [
                    { key: "notifications.historyLimit", label: "Keep", kind: "number", min: 10, max: 500, step: 10, suffix: " notifications" },
                    { key: "notifications.historyMaxAgeHours", label: "Remove after", kind: "number", min: 0, max: 720, step: 24, scale: 24, suffix: " d", zeroLabel: "Never", keywords: "history age" },
                    { key: "notifications.historyLowUrgency", label: "Keep low-urgency", kind: "bool", keywords: "history" },
                    { key: "notifications.games", label: "Games when empty", kind: "set", options: [
                        { value: "dino", label: "Dino" }, { value: "flappy", label: "Flappy" }
                    ] }
                ] }
            ]
        },
        {
            id: "quicksettings", title: "Quick Settings", glyph: "", tint: "qsBlue",
            groups: [
                { rows: [
                    { key: "quicksettings.sessionButton", label: "Session button", kind: "bool" },
                    { key: "quicksettings.editButton", label: "Edit button", kind: "bool" },
                    { key: "quicksettings.tray", label: "System tray", kind: "bool", keywords: "tray StatusNotifier" },
                    { key: "quicksettings.holdMs", label: "Hold to edit", kind: "number", min: 200, max: 1500, step: 50, scale: S, decimals: 2, suffix: " s" },
                    { key: "quicksettings.wheelStep", label: "Slider wheel step", kind: "number", min: 0.01, max: 0.2, step: 0.01, scale: 0.01, suffix: " %" }
                ] },
                { title: "Keep after reboot", footer: "Switched back to how it was before a reboot or a shell restart.", rows: [
                    { key: "persist.wifi", label: "Wi-Fi", kind: "bool", keywords: "remember restore reboot" },
                    { key: "persist.bluetooth", label: "Bluetooth", kind: "bool", keywords: "remember restore reboot" },
                    { key: "persist.airplane", label: "Airplane Mode", kind: "bool", keywords: "remember restore reboot" },
                    { key: "persist.caffeine", label: "Caffeine", kind: "bool", keywords: "remember restore reboot" }
                ] }
            ]
        },
        {
            id: "osd", title: "Volume & Brightness", glyph: "", tint: "settingsPink",
            groups: [
                { title: "On-screen display", footer: "Shown on any change, from keys or other apps. Quick Settings sliders stay quiet.", rows: [
                    { key: "osd.watch", label: "Show on change", kind: "bool" },
                    { key: "osd.watchMicVolume", dependsOn: "osd.watch", label: "Microphone volume too", kind: "bool" },
                    { key: "timings.osdAutoCloseMs", label: "Hide after", kind: "number", min: 500, max: 5000, step: 100, scale: S, decimals: 1, suffix: " s" }
                ] },
                { title: "Steps", footer: "Volume step and limits are in Sound.", rows: [
                    { key: "brightness.step", label: "Brightness step", kind: "number", min: 0.01, max: 0.25, step: 0.01, scale: 0.01, suffix: " %" },
                    { key: "persist.brightness", label: "Keep brightness after reboot", kind: "bool", keywords: "remember restore" }
                ] }
            ]
        },
        {
            // Outputs are generated (SettingsDisplays.js, services/Displays):
            // the arrangement widget, one page per output, Apply / Keep.
            id: "displays", title: "Displays", glyph: "\uea89", tint: "qsBlue",
            groups: [
                { generate: "displayArrangement", footer: "Drag a display to move it, tap it for its resolution, scale and rotation.", rows: [] },
                { generate: "displayList", footerFrom: "displays", rows: [] },
                { generate: "displayApply", rows: [] },
                { title: "Saved layouts", footer: "A kept change is saved for this set of displays and comes back whenever they are connected together.", rows: [
                    { key: "displays.restore", label: "Restore saved layouts", kind: "bool", keywords: "monitor profile kanshi" },
                    { key: "displays.confirmSec", label: "Revert unconfirmed changes after", kind: "number", min: 5, max: 60, step: 5, suffix: " s" },
                    { kind: "action", label: "Forget saved layouts", action: "displayForget", destructive: true, confirm: "Tap again to forget" }
                ] }
            ]
        },
        {
            // services/NightLight; footer = today's sun times or why the
            // schedule cannot run.
            id: "nightLight", title: "Night Light", glyph: "\uece7", tint: "qsOrange",
            groups: [
                { footerFrom: "nightLight", rows: [
                    { key: "nightLight.schedule", label: "Schedule", kind: "choice", segments: true, keywords: "night shift blue light gamma redshift wlsunset gammastep", options: [
                        { value: "sun", label: "Sunset to sunrise" }, { value: "custom", label: "Custom" }, { value: "off", label: "Off" }
                    ] }
                ] },
                { title: "Custom hours", dependsOn: "!nightLight.schedule=off", footer: "Sunset to sunrise uses these hours too until the location is known (the Weather location in Dashboard).", rows: [
                    { key: "nightLight.from", label: "Turn on at", kind: "number", time: true, min: 0, max: 1425, step: 15 },
                    { key: "nightLight.to", label: "Turn off at", kind: "number", time: true, min: 0, max: 1425, step: 15 },
                    { key: "nightLight.transitionMin", label: "Fade over", kind: "number", min: 0, max: 120, step: 5, suffix: " min", zeroLabel: "Instant" }
                ] },
                { title: "Colour", footer: "6500 K = the colours untouched. Dragging the slider in Quick Settings previews the warmth even while Night Light is off.", rows: [
                    { key: "nightLight.temperature", label: "Night warmth", kind: "number", min: 1900, max: 6000, step: 100, suffix: " K", slider: true, keywords: "temperature kelvin" },
                    { key: "nightLight.dayTemperature", label: "Day temperature", kind: "number", min: 4500, max: 6500, step: 100, suffix: " K" }
                ] },
                { title: "Behaviour", footer: "A tap against the schedule lasts until its next turn: on until the morning, off until the evening.", rows: [
                    { key: "nightLight.fadeMs", label: "Fade on toggle", kind: "number", min: 0, max: 5000, step: 200, scale: S, decimals: 1, suffix: " s", zeroLabel: "Instant" },
                    { key: "nightLight.pauseFullscreen", label: "Day colours in fullscreen", kind: "bool", keywords: "games video" }
                ] }
            ]
        },
        {
            // Devices / app outputs are generated (SettingsAudio.js);
            // store "wp" = WirePlumber settings (wpctl settings --save),
            // "audioPolicy" = services/AudioPolicy session state.
            id: "sound", title: "Sound", glyph: "\ueb51", tint: "accentRed",
            groups: [
                { title: "Output", generate: "audioOutputs", footer: "In priority order: when the device in use goes away, the first available one takes over. Tap a device for its name, profile, balance and test.", rows: [] },
                { title: "Input", generate: "audioInputs", rows: [] },
                { title: "Switching", rows: [
                    { key: "audio.autoSwitch", label: "New device", kind: "choice", segments: true, keywords: "auto switch headphones plug connect", options: [
                        { value: "always", label: "Switch" }, { value: "ask", label: "Ask" }, { value: "never", label: "Stay" }
                    ] },
                    { key: "audio.followPriority", label: "Fall back in the list order", kind: "bool", keywords: "priority" },
                    { store: "wp", key: "linking.pause-playback", label: "Pause when the output goes away", kind: "bool", keywords: "unplug headphones" },
                    { store: "wp", key: "device.routes.mute-on-alsa-playback-removed", label: "Mute after unplugging headphones", kind: "bool" },
                    { store: "wp", key: "device.routes.mute-on-bluetooth-playback-removed", label: "Mute after Bluetooth disconnects", kind: "bool" },
                    { store: "wp", key: "node.stream.restore-target", label: "Remember each app's output", kind: "bool", keywords: "route stream" },
                    { key: "persist.volume", label: "Keep volume after reboot", kind: "bool", keywords: "remember restore" }
                ] },
                { title: "Bluetooth", footer: "While any headset has Music or Calls pinned (its page above, or the lock in Quick Settings), call mode on recording is paused for every headset.", rows: [
                    { store: "wp", key: "bluetooth.autoswitch-to-headset-profile", label: "Call mode when an app records", kind: "bool", keywords: "headset hfp profile microphone" },
                    { key: "audio.btReturnToMusic", label: "Back to music after a call", kind: "bool", keywords: "a2dp profile" },
                    { key: "audio.btReturnDelayMs", dependsOn: "audio.btReturnToMusic", label: "After", kind: "number", min: 1000, max: 60000, step: 1000, scale: S, suffix: " s" },
                    { store: "wp", key: "bluetooth.profile-preference", label: "Prefer", kind: "choice", segments: true, keywords: "codec quality latency", options: [
                        { value: "quality", label: "Quality" }, { value: "latency", label: "Latency" }
                    ] }
                ] },
                { title: "Volume", footer: "Headphone limit 0 = the same as the maximum. The on-screen display is in Volume & Brightness.", rows: [
                    { key: "audio.volumeStep", label: "Volume step", kind: "number", min: 0.01, max: 0.2, step: 0.01, scale: 0.01, suffix: " %" },
                    { key: "audio.maxVolume", label: "Maximum volume", kind: "number", min: 1, max: 1.5, step: 0.05, scale: 0.01, suffix: " %", keywords: "limit boost" },
                    { key: "audio.maxVolumeHeadphones", label: "Headphone limit", kind: "number", min: 0, max: 1.5, step: 0.05, scale: 0.01, suffix: " %", keywords: "hearing cap" },
                    { key: "audio.eventVolume", label: "System sounds", kind: "number", slider: true, min: 0, max: 1, step: 0.05, scale: 0.01, suffix: " %", keywords: "notification" },
                    { store: "wp", key: "node.features.audio.mono", label: "Mono audio", kind: "bool", keywords: "accessibility one ear" }
                ] },
                { title: "Microphone", footer: "Voice processing = WebRTC noise and echo suppression on the microphone in use. Listen to yourself works on headphones only (speakers would howl).", rows: [
                    { key: "audio.voice.enabled", label: "Voice processing", kind: "bool", keywords: "noise suppression echo cancellation rnnoise" },
                    { key: "audio.voice.gainControl", dependsOn: "audio.voice.enabled", label: "Automatic gain", kind: "bool", keywords: "agc" },
                    { store: "audioPolicy", key: "listening", dependsOn: "audioPolicy:canListen", label: "Listen to yourself", kind: "bool", keywords: "monitor loopback test" },
                    { key: "audio.micExclude", label: "Not a mic in use", kind: "text", array: true, wide: true, allowEmpty: true, placeholder: "dsp", keywords: "indicator privacy exclude" }
                ] },
                { title: "App outputs", generate: "audioRoutes", footer: "Outputs WirePlumber remembers per app. Forgetting one restarts WirePlumber: sound pauses for a second.", rows: [] }
            ]
        },
        {
            id: "keyboard", title: "Keyboard", glyph: "", tint: "settingsGrey",
            groups: [
                { footer: "A pill under the text cursor when the layout or Caps Lock changes.", dependsOn: "keyboard.enabled", rows: [
                    { key: "keyboard.enabled", label: "Keyboard pill", kind: "bool" },
                    { key: "keyboard.layout", label: "On layout switch", kind: "bool" },
                    { key: "keyboard.caps", label: "On Caps Lock", kind: "bool" },
                    { key: "keyboard.followCaret", label: "Follow the text cursor", kind: "bool" },
                    { key: "keyboard.layoutShowMs", label: "Show for", kind: "number", min: 300, max: 5000, step: 100, scale: S, decimals: 1, suffix: " s" }
                ] },
                { title: "Touch Bar", footer: "Macs with tiny-dfr: a held Touch Bar button pushes a tab out of the bottom screen edge above it. Suction = the curve joining it to the edge. Needs the udev rule from scripts/touchbar.", dependsOn: "touchBar.enabled", rows: [
                    { key: "touchBar.enabled", label: "Press tabs", kind: "bool", keywords: "touchbar tiny-dfr" },
                    { key: "touchBar.widthMode", label: "Width", kind: "choice", segments: true, options: [
                        { value: "fixed", label: "Fixed" }, { value: "button", label: "Button" }
                    ] },
                    { key: "touchBar.width", dependsOn: "touchBar.widthMode=fixed", label: "Tab width", kind: "number", min: 8, max: 400, step: 2, suffix: " px" },
                    { key: "touchBar.height", label: "Tab height", kind: "number", min: 2, max: 80, step: 1, suffix: " px" },
                    { key: "touchBar.radius", label: "Corner radius", kind: "number", min: 0, max: 40, step: 1, suffix: " px" },
                    { key: "touchBar.suctionSpread", label: "Suction along the screen", kind: "number", min: 0, max: 120, step: 1, suffix: " px", keywords: "fillet" },
                    { key: "touchBar.suctionRise", label: "Suction up the tab", kind: "number", min: 0, max: 60, step: 1, suffix: " px", keywords: "fillet" },
                    { key: "touchBar.suctionStrength", label: "Suction strength", kind: "number", slider: true, min: 0, max: 1, step: 0.01, scale: 0.01, suffix: " %", keywords: "fillet" },
                    { key: "touchBar.span", label: "Bar span", kind: "number", slider: true, min: 0.3, max: 1, step: 0.01, scale: 0.01, suffix: " %" },
                    { key: "touchBar.offset", label: "Bar offset", kind: "number", slider: true, min: -0.2, max: 0.2, step: 0.005, scale: 0.01, decimals: 1, suffix: " %" },
                    { key: "touchBar.screens", label: "Screens", kind: "choice", segments: true, options: [
                        { value: "internal", label: "Built-in" }, { value: "all", label: "All" }
                    ] }
                ] }
            ]
        },
        {
            id: "haptics", title: "Haptics", glyph: "", tint: "settingsPurple",
            groups: [
                { footer: "Trackpad feedback. auto = the first backend that works on this machine.", dependsOn: "haptics.enabled", rows: [
                    { key: "haptics.enabled", label: "Haptics", kind: "bool" },
                    { key: "haptics.backend", label: "Backend", kind: "choice", options: [
                        { value: "auto", label: "Automatic" }, { value: "evdev-haptic", label: "evdev-haptic" }, { value: "apple-t2", label: "apple-t2" }
                    ] }
                ] },
                { title: "Strength", dependsOn: "haptics.enabled", rows: [
                    { key: "haptics.intensity.click", label: "Click", kind: "number", slider: true, min: 0, max: 1, step: 0.05, scale: 0.01, suffix: " %" },
                    { key: "haptics.intensity.deep", label: "Deep press", kind: "number", slider: true, min: 0, max: 1, step: 0.05, scale: 0.01, suffix: " %" },
                    { key: "haptics.intensity.release", label: "Release", kind: "number", slider: true, min: 0, max: 1, step: 0.05, scale: 0.01, suffix: " %" },
                    { key: "haptics.intensity.tick", label: "Tick", kind: "number", slider: true, min: 0, max: 1, step: 0.05, scale: 0.01, suffix: " %" }
                ] },
                { title: "Where", dependsOn: "haptics.enabled", footer: "Steps: a tick each time volume / brightness reaches a multiple of \"Tick every\" (equal to the volume step = every press).", rows: [
                    { key: "haptics.quickSettings", label: "Quick Settings", kind: "bool" },
                    { key: "haptics.dashboard", label: "Dashboard", kind: "bool" },
                    { key: "haptics.limits", label: "Volume / brightness limits", kind: "bool" },
                    { key: "haptics.osdSteps", label: "Volume / brightness steps", kind: "bool" },
                    { key: "haptics.osdStepEvery", dependsOn: "haptics.osdSteps", label: "Tick every", kind: "number", min: 1, max: 50, step: 1, suffix: " %" },
                    { key: "haptics.polkit", label: "Authentication", kind: "bool" },
                    { key: "haptics.wallpapers", label: "Wallpaper carousel", kind: "bool" },
                    { key: "haptics.timer", label: "Timer ruler", kind: "bool" },
                    { key: "haptics.recordSpeed", label: "Recording speed ruler", kind: "bool" }
                ] }
            ]
        }
    ],
    [
        {
            id: "launcher", title: "Launcher", glyph: "", tint: "qsBlue",
            groups: [
                { rows: [
                    { key: "launcher.disabled", label: "Plugins", kind: "set", invert: true, options: [
                        { value: "apps", label: "Apps" }, { value: "clipboard", label: "Clipboard" },
                        { value: "wallpapers", label: "Wallpapers" }, { value: "prompter", label: "Teleprompter" },
                        { value: "calc", label: "Calculator" }
                    ] },
                    { key: "launcher.maxShown", label: "Results shown", kind: "number", min: 3, max: 12, step: 1 },
                    { key: "launcher.magicSymbol", label: "Plugin prefix", kind: "text" },
                    { key: "launcher.apps.terminal", label: "Terminal", kind: "text", array: true, keywords: "kitty foot" }
                ] },
                { title: "Clipboard", footer: "auto = own wl-paste watchers unless the compositor runs one.", rows: [
                    { key: "launcher.clipboard.historyLimit", label: "Keep", kind: "number", min: 10, max: 1000, step: 10, suffix: " items" },
                    { key: "launcher.clipboard.autoPaste", label: "Paste after picking", kind: "bool" },
                    { key: "launcher.clipboard.pasteCommand", dependsOn: "launcher.clipboard.autoPaste", label: "Paste command", kind: "text" },
                    { key: "launcher.clipboard.watch", label: "Watch clipboard", kind: "choice", segments: true, options: [
                        { value: "auto", label: "Auto" }, { value: true, label: "On" }, { value: false, label: "Off" }
                    ] }
                ] },
                { title: "Calculator", footer: "Type 2^10, 15% of 200, 5 usd to rub, 90 min or days until 31.12 in the search; = forces it. Enter copies, Alt+Enter pastes.", rows: [
                    { key: "launcher.calc.enabled", label: "Calculate while typing", kind: "bool" },
                    { key: "launcher.calc.currencies", dependsOn: "launcher.calc.enabled", label: "Currencies", kind: "text", array: true, keywords: "rub usd eur exchange rates" },
                    { key: "launcher.calc.angle", dependsOn: "launcher.calc.enabled", label: "Angles", kind: "choice", segments: true, options: [
                        { value: "deg", label: "Degrees" }, { value: "rad", label: "Radians" }
                    ] },
                    { key: "launcher.calc.historyLimit", label: "History", kind: "number", min: 0, max: 500, step: 10, suffix: " items" }
                ] }
            ]
        },
        {
            id: "wallpapers", title: "Wallpapers", glyph: "", tint: "settingsCyan",
            groups: [
                { title: "Library", rows: [
                    { key: "launcher.wallpapers.dirs", label: "Folders", kind: "text", array: true },
                    { key: "launcher.wallpapers.recursive", label: "Include subfolders", kind: "bool" },
                    { key: "launcher.wallpapers.semanticSearch", label: "Search by description", kind: "bool" }
                ] }
            ].concat(wallGroups())
        },
        {
            id: "dashboard", title: "Dashboard", glyph: "", tint: "qsIndigo",
            groups: [
                { title: "Weather", rows: [
                    { key: "dashboard.weatherLocation", label: "Location", kind: "text" },
                    { key: "dashboard.useFahrenheit", label: "Units", kind: "choice", segments: true, options: [
                        { value: false, label: "°C" }, { value: true, label: "°F" }
                    ] }
                ] },
                { title: "Sensors", footer: "Temperatures above these turn the sensor yellow, then red.", rows: [
                    { key: "dashboard.tempWarm", label: "Warm", kind: "number", min: 40, max: 100, step: 5, suffix: " °C" },
                    { key: "dashboard.tempHot", label: "Hot", kind: "number", min: 50, max: 110, step: 5, suffix: " °C" }
                ] }
            ]
        },
        {
            id: "capture", title: "Capture", glyph: "", tint: "settingsGrey",
            groups: [
                { title: "Screenshots", rows: [
                    { key: "capture.defaultMode", label: "Opens in", kind: "choice", options: [
                        { value: "shot", label: "Screenshot" }, { value: "record", label: "Recording" },
                        { value: "window", label: "Window" }, { value: "color", label: "Colour picker" },
                        { value: "scan", label: "Scan" }, { value: "ai", label: "AI" }
                    ] },
                    { key: "capture.saveDir", label: "Save to", kind: "text" },
                    { key: "capture.copyToClipboard", label: "Copy to clipboard", kind: "bool" },
                    { key: "capture.smartRegions", label: "Smart regions", kind: "bool" },
                    { key: "capture.ocrDefaultLang", label: "Text recognition", kind: "choice", options: [
                        { value: "auto", label: "Last used" }, { value: "all", label: "All languages" },
                        { value: "eng", label: "English" }, { value: "rus", label: "Russian" }, { value: "eng+rus", label: "English + Russian" }
                    ] }
                ] },
                { title: "Recording", rows: [
                    { key: "recorder.recordDir", label: "Save to", kind: "text" },
                    { key: "recorder.audioDefault", label: "Audio", kind: "choice", options: [
                        { value: "auto", label: "Last choice" }, { value: "none", label: "None" },
                        { value: "system", label: "System" }, { value: "mic", label: "Microphone" }, { value: "both", label: "System + microphone" }
                    ] },
                    { key: "recorder.maxFps", label: "Frame rate", kind: "choice", segments: true, options: opts([30, 60, 120]) },
                    { key: "recorder.hwAccel", label: "Hardware encoding", kind: "bool" },
                    { key: "recorder.region.show", label: "Dim outside the region", kind: "bool" }
                ] }
            ]
        },
        {
            id: "dictation", title: "Dictation", glyph: "", tint: "qsOrange",
            groups: [
                { footer: "Following the layout pins the language to it: faster and more accurate, but speak the layout's language.", rows: [
                    { key: "dictation.followLayout", label: "Language from layout", kind: "bool" },
                    { key: "dictation.language", dependsOn: "!dictation.followLayout", label: "Language", kind: "choice", options: LANGS },
                    { key: "dictation.typeEnabled", label: "Type the text", kind: "bool" },
                    { key: "dictation.typeDelayMs", dependsOn: "dictation.typeEnabled", label: "Typing delay", kind: "number", min: 0, max: 50, step: 1, suffix: " ms" }
                ] },
                { title: "Refine", footer: "A local LLM cleans up punctuation and slips. Keep it loaded to skip the ~20 s cold start.", dependsOn: "dictation.refineEnabled", rows: [
                    { key: "dictation.refineEnabled", label: "Refine with LLM", kind: "bool" },
                    { key: "dictation.refineModel", label: "Model", kind: "text" },
                    { key: "dictation.refineIdleTtlS", label: "Keep loaded", kind: "number", min: 0, max: 3600, step: 60, scale: 60, suffix: " min" }
                ] },
                { title: "Transcription", rows: [
                    { key: "", label: "File transcription", kind: "page", page: {
                        title: "File transcription",
                        groups: [
                            { footer: "WhisperX on the CPU. Bigger models are slower and more accurate.", rows: [
                                { key: "transcribe.model", label: "Model", kind: "choice", options: opts(["tiny", "base", "small", "medium", "large-v3", "large-v3-turbo"]) },
                                { key: "transcribe.language", label: "Language", kind: "choice", options: LANGS },
                                { key: "transcribe.computeType", label: "Precision", kind: "choice", segments: true, options: opts(["int8", "float16", "float32"]) },
                                { key: "transcribe.vad", label: "Voice detection", kind: "choice", segments: true, options: opts(["pyannote", "silero"]) },
                                { key: "transcribe.align", label: "Word timings", kind: "bool" }
                            ] },
                            { title: "Speakers", footer: "Needs a Hugging Face token and the accepted pyannote terms.", dependsOn: "transcribe.diarize", rows: [
                                { key: "transcribe.diarize", label: "Tell speakers apart", kind: "bool" },
                                { key: "transcribe.minSpeakers", label: "At least", kind: "number", min: 0, max: 10, step: 1 },
                                { key: "transcribe.maxSpeakers", label: "At most", kind: "number", min: 0, max: 10, step: 1 }
                            ] }
                        ]
                    } }
                ] }
            ]
        },
        {
            id: "stash", title: "Stash & LocalSend", glyph: "", tint: "accentYellow",
            groups: [
                { title: "Stash", rows: [
                    { key: "stash.dropMode", label: "Dropped files", kind: "choice", segments: true, options: [
                        { value: "copy", label: "Copy" }, { value: "symlink", label: "Link" }
                    ] }
                ] },
                { title: "LocalSend", footer: "Incoming transfers ask for confirmation in the island.", dependsOn: "stash.localsend", rows: [
                    { key: "stash.localsend", label: "LocalSend", kind: "bool" },
                    { key: "stash.receive", label: "Receive files", kind: "bool" },
                    { key: "stash.alias", label: "Device name", kind: "text" },
                    { key: "stash.downloadDir", label: "Save to", kind: "text" }
                ] }
            ]
        },
        {
            id: "timer", title: "Timer", glyph: "", tint: "timerAccent",
            groups: [
                { rows: [
                    { key: "timer.defaultMinutes", label: "Default", kind: "number", min: 1, max: 120, step: 1, suffix: " min" },
                    { key: "timer.maxMinutes", label: "Ruler up to", kind: "number", min: 10, max: 600, step: 10, suffix: " min" },
                    { key: "timer.openOnFinish", label: "Open when done", kind: "bool" }
                ] },
                { title: "Alarm", rows: [
                    { key: "timer.alarmSound", label: "Sound", kind: "text" },
                    { key: "timer.alarmMaxSec", label: "Ring for at most", kind: "number", min: 5, max: 300, step: 5, suffix: " s" }
                ] }
            ]
        },
        {
            id: "shazam", title: "Shazam", glyph: "", tint: "shazam",
            groups: [
                { footer: "Automatic listens to what the computer plays, the microphone when it is silent.", rows: [
                    { key: "shazam.source", label: "Listen to", kind: "choice", segments: true, options: [
                        { value: "auto", label: "Auto" }, { value: "monitor", label: "Computer" }, { value: "mic", label: "Microphone" }
                    ] },
                    { key: "shazam.maxSec", label: "Give up after", kind: "number", min: 5, max: 60, step: 5, suffix: " s" },
                    { key: "shazam.historyLimit", label: "Keep", kind: "number", min: 10, max: 500, step: 10, suffix: " songs" }
                ] }
            ]
        },
        {
            id: "prompter", title: "Teleprompter", glyph: "", tint: "qsGreen",
            groups: [
                { footer: "Voice follows your speech, auto scrolls at the set pace, manual waits for the wheel.", rows: [
                    { key: "prompter.mode", label: "Scrolling", kind: "choice", segments: true, options: [
                        { value: "voice", label: "Voice" }, { value: "auto", label: "Auto" }, { value: "manual", label: "Manual" }
                    ] },
                    { key: "prompter.wpm", dependsOn: "prompter.mode=auto", label: "Auto pace", kind: "number", min: 60, max: 260, step: 10, suffix: " wpm" },
                    { key: "prompter.language", dependsOn: "prompter.mode=voice", label: "Voice language", kind: "choice", options: LANGS },
                    { key: "prompter.dir", label: "Scripts folder", kind: "text" }
                ] }
            ]
        }
    ],
    [
        {
            id: "battery", title: "Battery", glyph: "", tint: "qsGreen",
            groups: [
                { footer: "Charge limit 0 = read it from the system (100 % without one).", rows: [
                    { key: "battery.warnPercent", label: "Warning at", kind: "number", min: 5, max: 80, step: 5, suffix: " %" },
                    { key: "battery.lowPercent", label: "Low at", kind: "number", min: 5, max: 50, step: 1, suffix: " %" },
                    { key: "battery.criticalPercent", label: "Critical at", kind: "number", min: 1, max: 20, step: 1, suffix: " %" },
                    { key: "battery.chargeLimit", label: "Charge limit", kind: "number", min: 0, max: 100, step: 5, suffix: " %" }
                ] }
            ]
        },
        {
            id: "idle", title: "Auto-Lock & Sleep", glyph: "\ueaf8", tint: "settingsPurple",
            groups: [
                { footer: "Counted from the last key press or pointer move. A dim at or after the lock is skipped.", footerFrom: "idleHolders", rows: [
                    { key: "idle.enabled", label: "Auto-lock and sleep", kind: "bool", keywords: "idle timeout dim screensaver hypridle swayidle" }
                ] },
                { title: "On power adapter", dependsOn: "idle.enabled", rows: IDLE_ROWS("ac") },
                { title: "On battery", dependsOn: "idle.enabled", rows: IDLE_ROWS("battery") },
                { title: "Behaviour", dependsOn: "idle.enabled", rows: [
                    { key: "idle.lockWarnSec", label: "Countdown before locking", kind: "number", min: 0, max: 60, step: 5, suffix: " s", zeroLabel: "Off" },
                    { key: "idle.lockedScreenOffSec", label: "Screen off when locked", kind: "number", min: 0, max: 600, step: 10, suffix: " s", zeroLabel: "Never" },
                    { key: "idle.dimLevel", label: "Dim to", kind: "number", min: 0.05, max: 0.9, step: 0.05, scale: 0.01, suffix: " %", slider: true },
                    { key: "idle.sleepAction", label: "Sleep means", kind: "choice", segments: true, options: [
                        { value: "suspend", label: "Sleep" }, { value: "hibernate", label: "Hibernate" }
                    ] }
                ] },
                { title: "Stay awake for", dependsOn: "idle.enabled", footer: "Apps: video players and browsers ask for it themselves. Sleep still waits for the tasks chosen below.", rows: [
                    { key: "idle.appInhibitors", label: "Apps that ask", kind: "bool", keywords: "inhibit video" },
                    { key: "idle.fullscreen", label: "Fullscreen windows", kind: "bool", keywords: "games video" },
                    { key: "idle.media", label: "Playing media", kind: "choice", options: [
                        { value: "none", label: "No" }, { value: "sleep", label: "Only keep awake" }, { value: "all", label: "Also no dim or lock" }
                    ] },
                    { key: "idle.sleepWaitsFor", label: "Sleep waits for", kind: "set", options: [
                        { value: "timer", label: "Timer" }, { value: "recordSaving", label: "Saving a recording" },
                        { value: "transcribe", label: "Transcription" }, { value: "localSend", label: "LocalSend" },
                        { value: "pacman", label: "Package manager" }, { value: "download", label: "Downloads" },
                        { value: "modelDownload", label: "Model downloads" }, { value: "wallpaperIndex", label: "Wallpaper indexing" }
                    ] },
                    { key: "idle.logindLock", label: "Lock on loginctl lock-session", kind: "bool" }
                ] },
                { title: "Caffeine", footer: "Holds everything above. Also in Quick Settings and IPC idle caffeineFor <min>.", rows: [
                    { key: "caffeine.minutes", label: "A tap keeps it on", kind: "number", min: 0, max: 480, step: 15, suffix: " min", zeroLabel: "Until off" },
                    { key: "caffeine.offBelowPercent", label: "Off on battery at", kind: "number", min: 0, max: 50, step: 5, suffix: " %", zeroLabel: "Never" }
                ] }
            ]
        },
        {
            id: "session", title: "Lock & Session", glyph: "", tint: "qsBlue",
            groups: [
                { title: "Lock screen", rows: [
                    { key: "lock.dissolve", label: "Dissolve windows", kind: "bool" },
                    { key: "lock.fingerprint", label: "Unlock with fingerprint", kind: "bool" },
                    { key: "lock.avatar", label: "Avatar", kind: "text" }
                ] },
                { title: "Session menu", rows: [
                    { key: "session.actions", label: "Actions", kind: "set", options: [
                        { value: "lock", label: "Lock" }, { value: "logout", label: "Log Out" },
                        { value: "suspend", label: "Sleep" }, { value: "hibernate", label: "Hibernate" },
                        { value: "reboot", label: "Restart" }, { value: "poweroff", label: "Shut Down" }
                    ] },
                    { key: "session.defaultAction", label: "Selected first", kind: "choice", options: [
                        { value: "lock", label: "Lock" }, { value: "logout", label: "Log Out" },
                        { value: "suspend", label: "Sleep" }, { value: "hibernate", label: "Hibernate" },
                        { value: "reboot", label: "Restart" }, { value: "poweroff", label: "Shut Down" }
                    ] },
                    { key: "session.confirm", label: "Confirm", kind: "bool" },
                    { key: "session.lockOnSuspend", label: "Lock before sleep", kind: "bool" }
                ] },
                { title: "Authentication", rows: [
                    { key: "polkit.enabled", label: "Polkit agent", kind: "bool" },
                    { key: "polkit.preferCurrentUser", dependsOn: "polkit.enabled", label: "Ask for my password first", kind: "bool" }
                ] }
            ]
        },
        {
            id: "network", title: "Network", glyph: "", tint: "qsBlue",
            groups: [
                { rows: [
                    { key: "network.hotspotName", label: "Hotspot name", kind: "text" },
                    { key: "network.portalUrl", label: "Captive portal page", kind: "text" }
                ] },
                { title: "Bluetooth", footer: "Turned off when nothing has been connected this long. 0 = never.", rows: [
                    { key: "bluetooth.autoOffMin", label: "Turn off when idle", kind: "number", min: 0, max: 60, step: 1, suffix: " min", keywords: "bluetooth battery auto off" }
                ] }
            ]
        },
        {
            id: "vpn", title: "VPN", glyph: "\ued58", tint: "qsBlue",
            groups: [
                { footerFrom: "vpnStatus", footer: "Servers and the subscription are in the VPN panel of Quick Settings. The kill switch keeps traffic blocked if sing-box dies, until the VPN is back or switched off.", rows: [
                    { store: "vpn", key: "status", label: "Status", kind: "info", options: [
                        { value: "inactive", label: "Off" }, { value: "connecting", label: "Connecting…" },
                        { value: "active", label: "Connected" }, { value: "offline", label: "No connection" },
                        { value: "disconnecting", label: "Disconnecting…" }, { value: "failed", label: "Failed" },
                        { value: "blocked", label: "Kill switch · traffic blocked" }, { value: "unavailable", label: "sing-box is not installed" }
                    ] },
                    { store: "vpn", key: "on", label: "VPN", kind: "bool", dependsOn: ["vpn:installed", "!vpn:busy"] },
                    { store: "vpn", key: "profile", label: "Server", kind: "choice", optionsFrom: "vpnProfiles", dependsOn: ["vpn:hasProfiles", "!vpn:busy"], keywords: "node" },
                    { kind: "action", label: "Update subscription", action: "vpnUpdate", keywords: "servers nodes" },
                    { store: "vpn", key: "enabled", label: "Start at boot", kind: "bool", dependsOn: ["vpn:installed", "!vpn:busy"], keywords: "autostart" },
                    { store: "vpn", key: "killswitch", label: "Kill switch", kind: "bool", dependsOn: ["vpn:installed", "!vpn:busy"] }
                ] },
                { title: "Routing", footer: "Where traffic that no rule matches goes. The local network always goes direct.", rows: [
                    { key: "vpn.routing.final", label: "Everything else", kind: "choice", segments: true, keywords: "split final", options: [
                        { value: "proxy", label: "Proxy" }, { value: "direct", label: "Direct" }
                    ] }
                ] },
                { title: "Rules", generate: "vpnRules", rows: [] },
                { footerFrom: "vpnApply", footer: "Routing and the sing-box overlay take effect on Apply: sing-box restarts, a config it cannot start with is rolled back.", rows: [
                    { kind: "action", label: "Apply changes", action: "vpnApply", keywords: "routing" },
                    { kind: "action", label: "Discard routing changes", action: "vpnDiscard", keywords: "revert undo" },
                    { kind: "action", label: "Re-download rule lists", action: "vpnRefresh", keywords: "geosite geoip" },
                    { kind: "action", label: "Edit sing-box overlay", action: "vpnEdit", keywords: "config json custom" },
                    { kind: "action", label: "Logs", action: "vpnLogs", keywords: "journal" }
                ] },
                { title: "Connection check", footer: "Ping and the speed test go through whatever route is up: the VPN's when it is on.", rows: [
                    { kind: "action", label: "Ping", action: "vpnPing", keywords: "latency" },
                    { kind: "action", label: "Speed test", action: "vpnSpeed", keywords: "speedtest bandwidth" },
                    { key: "quicksettings.vpn.stallMs", label: "No connection after", kind: "number", min: 3000, max: 60000, step: 1000, scale: S, suffix: " s" }
                ] }
            ]
        }
    ]
];

const SECTIONS = [].concat(...SIDEBAR);

// Group dependsOn → its rows (once, at load: search results copy rows).
function spreadDeps(groups) {
    for (const g of groups) {
        for (const row of g.rows) {
            if (row.kind === "page") {
                for (const pg of row.page.groups)
                    pg.dependsOn = pg.dependsOn ?? g.dependsOn;
                spreadDeps(row.page.groups);
            }
            if (g.dependsOn && !row.dependsOn && ![].concat(g.dependsOn).includes(row.key))
                row.dependsOn = g.dependsOn;
        }
    }
}
for (const s of SECTIONS)
    spreadDeps(s.groups);

function section(id) {
    return SECTIONS.find(s => s.id === id) ?? SECTIONS[0];
}
