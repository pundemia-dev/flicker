import QtQuick
import Quickshell
import Quickshell.Io
import "../config"
import "SunTimes.js" as SunTimes

// Night Light (Oct 2026): warm colour temperature at night, no wlsunset /
// gammastep — scripts/nightlight/gammad.py is a bare wlr-gamma-control
// client (niri, driftwm, Hyprland, sway); this service owns the schedule
// and sends it per-output targets. Ideas taken from:
//   wlsunset / DMS   colour model (illuminant D + Planckian locus) and the
//                    sun schedule: the fade runs while the sun goes from
//                    +3° to civil twilight (-6°) — follows the real sky
//   noctalia         wall-clock anchored ramps (same result whenever the
//                    shell started), upload budget (each set_gamma stalls
//                    the compositor 1-2 vblanks: fades are rate-capped)
//   end-4 / macOS /  a manual toggle overrides only until the schedule's
//   GNOME            next turn ("on until sunrise", "off until tonight"),
//                    then the schedule takes over without a jump
//   KDE              warmth preview while dragging the slider
//   DMS              re-send after a resume from suspend
// Own: fades in mired space (even to the eye; a kelvin lerp rushes the
// warm end), schedule steps eased by the helper between ticks (a slow
// continuous ramp, ~10 K per upload), per-output pause for fullscreen
// windows, coordinates from Weather cached for offline starts.
//
// `schedule`: "sun" (Weather's coordinates; none yet → the custom hours),
// "custom" (from → to, `transitionMin` fade inside the window), "off"
// (manual only). Manual state / override / last coordinates survive a
// restart (statePath("nightlight.json")).
Scope {
    id: root

    required property var events
    property var weather: null
    property var compositor: null

    readonly property var defaults: ({
            schedule: "sun",
            temperature: 3400,
            dayTemperature: 6500,
            from: 1320,
            to: 420,
            transitionMin: 30,
            fadeMs: 1200,
            pauseFullscreen: false,
            sunDayElevation: 3,
            sunNightElevation: -6
        })
    readonly property var cfg: Object.assign({}, root.defaults, Config.data.nightLight ?? {})
    readonly property int nightK: Math.max(1900, Math.min(6500, root.cfg.temperature))
    readonly property int dayK: Math.max(4500, Math.min(6500, root.cfg.dayTemperature))

    // Helper state: false once the compositor says it has no gamma control.
    property bool available: true
    property var outputs: []
    // Outputs whose control the compositor refused (another gamma client).
    property var failed: []

    property bool manualOn: false
    // { on, until (epoch ms) }: a manual toggle against the schedule.
    property var override: null
    property real now: Date.now()

    property real lat: NaN
    property real lon: NaN
    readonly property bool hasLocation: !isNaN(root.lat) && !isNaN(root.lon)
    // Effective mode: the sun schedule falls back to the custom hours
    // while no coordinates were ever known.
    readonly property string mode: root.cfg.schedule === "sun" && !root.hasLocation ? "custom" : root.cfg.schedule
    readonly property bool sunFallback: root.cfg.schedule === "sun" && !root.hasLocation

    readonly property var weatherLat: root.weather?.latitude ?? NaN
    readonly property var weatherLon: root.weather?.longitude ?? NaN
    onWeatherLatChanged: root.takeLocation()
    onWeatherLonChanged: root.takeLocation()
    function takeLocation(): void {
        if (isNaN(root.weatherLat) || isNaN(root.weatherLon))
            return;
        if (Math.abs(root.weatherLat - root.lat) < 0.01 && Math.abs(root.weatherLon - root.lon) < 0.01)
            return;
        root.lat = root.weatherLat;
        root.lon = root.weatherLon;
        root.save();
    }

    // --- schedule -------------------------------------------------------

    // One local day's turns: eveStart → eveEnd = evening fade, mornStart →
    // mornEnd = morning fade. `cond` polarDay / polarNight = none.
    function dayEvents(d: var): var {
        const y = d.getFullYear(), m = d.getMonth(), day = d.getDate();
        if (root.mode === "sun") {
            const s = SunTimes.compute(root.lat, root.lon, d, root.cfg.sunDayElevation, root.cfg.sunNightElevation);
            if (s.cond !== "normal")
                return { cond: s.cond, list: [] };
            return { cond: "normal", list: [
                    { t: s.dawn, k: "mornStart" }, { t: s.sunrise, k: "mornEnd" },
                    { t: s.sunset, k: "eveStart" }, { t: s.dusk, k: "eveEnd" }] };
        }
        const from = root.cfg.from, to = root.cfg.to;
        const len = ((to - from) % 1440 + 1440) % 1440 || 1440;
        const tr = Math.max(0, Math.min(root.cfg.transitionMin, len / 2));
        // Date(…, minutes) keeps wall-clock times across DST changes.
        const start = new Date(y, m, day, 0, from).getTime();
        const end = new Date(y, m, day, 0, from + len).getTime();
        return { cond: "normal", list: [
                { t: start, k: "eveStart" }, { t: start + tr * 60000, k: "eveEnd" },
                { t: end - tr * 60000, k: "mornStart" }, { t: end, k: "mornEnd" }] };
    }

    // Night amount (0 day … 1 night) at `t` + the turns around it.
    function evaluate(t: real): var {
        const base = new Date(t);
        let list = [];
        let today = "normal";
        for (let i = -1; i <= 2; i++) {
            const e = root.dayEvents(new Date(base.getFullYear(), base.getMonth(), base.getDate() + i));
            if (i === 0)
                today = e.cond;
            list = list.concat(e.list);
        }
        list.sort((a, b) => a.t - b.t);
        let prev = null, next = null;
        for (const e of list) {
            if (e.t <= t)
                prev = e;
            else {
                next = e;
                break;
            }
        }
        let p = today === "polarNight" ? 1 : 0;
        if (prev && next) {
            const f = (t - prev.t) / Math.max(1, next.t - prev.t);
            p = prev.k === "eveStart" ? f : prev.k === "eveEnd" ? 1 : prev.k === "mornStart" ? 1 - f : 0;
        }
        return { p: Math.max(0, Math.min(1, p)), list: list };
    }

    readonly property var current: root.evaluate(root.now)
    readonly property bool overriding: !!root.override && root.override.until > root.now && root.mode !== "off"
    // What is shown: 0 = day temperature, 1 = night temperature.
    readonly property real level: root.mode === "off" ? (root.manualOn ? 1 : 0)
        : root.overriding ? (root.override.on ? 1 : 0) : root.current.p
    readonly property bool active: root.level > 0.001
    readonly property bool ramping: root.level > 0.001 && root.level < 0.999

    function mired(a: real, b: real, p: real): real {
        return 1e6 / (1e6 / a + (1e6 / b - 1e6 / a) * p);
    }
    function kelvinAt(level: real): int {
        const s = level * level * (3 - 2 * level);
        return Math.round(root.mired(root.dayK, root.nightK, s));
    }
    readonly property int kelvin: root.previewK > 0 ? root.previewK : root.kelvinAt(root.level)

    // The schedule's night amount over today (local midnight → +24 h),
    // `n` samples (eased like the temperature): the QS panel's strip.
    function timeline(n: int): var {
        const d = new Date(root.now);
        const t0 = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
        const out = [];
        for (let i = 0; i < n; i++) {
            const p = root.mode === "off" ? 0 : root.evaluate(t0 + (i + 0.5) * 86400000 / n).p;
            out.push(p * p * (3 - 2 * p));
        }
        return out;
    }
    readonly property real dayFraction: {
        const d = new Date(root.now);
        return (d.getHours() * 60 + d.getMinutes()) / 1440;
    }

    // The next morning / evening the user would name: the real sunrise /
    // sunset (sun at the horizon) or the custom hours. Epoch ms, 0 = none.
    function refTime(kind: string, after: real): real {
        const base = new Date(after);
        for (let i = 0; i <= 2; i++) {
            const d = new Date(base.getFullYear(), base.getMonth(), base.getDate() + i);
            let t = 0;
            if (root.mode === "sun") {
                const s = SunTimes.compute(root.lat, root.lon, d, 0, 0);
                t = s.cond === "normal" ? (kind === "morning" ? s.sunrise : s.sunset) : 0;
            } else {
                t = new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, kind === "morning" ? root.cfg.to : root.cfg.from).getTime();
            }
            if (t > after)
                return t;
        }
        return 0;
    }
    function hm(t: real): string {
        return t > 0 ? Qt.formatTime(new Date(t), "hh:mm") : "";
    }
    readonly property real sunrise: root.mode === "off" ? 0 : root.refTime("morning", root.now)
    readonly property real sunset: root.mode === "off" ? 0 : root.refTime("evening", root.now)

    readonly property string status: {
        if (!root.available)
            return I18n.tr("Unavailable");
        if (root.mode === "off")
            return root.active ? I18n.tr("On") : I18n.tr("Off");
        if (root.active) {
            const t = root.refTime("morning", root.now);
            return t > 0 ? I18n.tr("Until %1").arg(root.hm(t)) : I18n.tr("On");
        }
        if (root.overriding)
            return I18n.tr("Off until tomorrow");
        const t = root.refTime("evening", root.now);
        return t > 0 ? I18n.tr("From %1").arg(root.hm(t)) : I18n.tr("Off");
    }

    // --- control --------------------------------------------------------

    function toggle(): void {
        root.setActive(!root.active);
    }
    // Against the schedule = an override until its next turn the same way
    // (on → until the morning fade starts, off → until the evening fade):
    // the schedule then continues from exactly that level. With the
    // schedule = back to it.
    function setActive(on: bool): void {
        const t = Date.now();
        if (root.mode === "off") {
            root.manualOn = on;
            root.override = null;
        } else {
            const ev = root.evaluate(t);
            if ((ev.p > 0.001) === on) {
                root.override = null;
            } else {
                const n = ev.list.find(e => e.k === (on ? "mornStart" : "eveStart") && e.t > t);
                root.override = { on: on, until: n ? n.t : t + 12 * 3600000 };
            }
        }
        root.now = t;
        root.save();
        root.events.cancel(on ? "nightlight:off" : "nightlight:on");
        if (Config.data.events?.nightLight ?? true)
            root.events.post({
                key: on ? "nightlight:on" : "nightlight:off",
                icon: on ? "" : "", // tabler moon-stars / sun
                color: on ? "qsOrange" : "qsYellow",
                text: root.status
            });
    }

    // Warmth while dragging a slider, held `previewMs` after the last move
    // (KDE): shown even with the night light off.
    property int previewK: 0
    function preview(k: int): void {
        root.previewK = Math.max(1900, Math.min(6500, Math.round(k)));
        previewEnd.restart();
    }
    property Timer previewEnd: Timer {
        interval: 1500
        onTriggered: root.previewK = 0
    }

    // --- helper ---------------------------------------------------------

    // Target per output: fullscreen ones keep the day temperature
    // (`pauseFullscreen`), the rest the shown K.
    readonly property var temps: {
        const t = { "*": root.kelvin };
        if (root.cfg.pauseFullscreen && root.previewK === 0)
            for (const s of Quickshell.screens)
                if (root.compositor?.fullscreenOn(s.name))
                    t[s.name] = root.dayK;
        return t;
    }
    // Fade of the next push: user changes fadeMs, a preview follows the
    // pointer, a schedule tick eases over the whole tick (a continuous
    // ramp, the helper uploads only every 10 K).
    property real nextFade: -1
    onTempsChanged: root.push(root.nextFade >= 0 ? root.nextFade : root.previewK > 0 ? 120 : root.cfg.fadeMs)

    property string lastSent: ""
    function push(fade: real): void {
        root.nextFade = -1;
        const temps = JSON.stringify(root.temps);
        if (!helper.running || temps === root.lastSent)
            return;
        root.lastSent = temps;
        helper.write(`{"temps": ${temps}, "fade": ${Math.round(fade)}}\n`);
    }
    // After a resume the compositor's gamma state is unknown (DMS #1235).
    function reapply(): void {
        if (helper.running)
            helper.write('{"reapply": true}\n');
        root.tick();
    }
    function tick(): void {
        root.nextFade = ticker.interval + 1000;
        root.now = Date.now();
        root.nextFade = -1;
        if (root.override && root.override.until <= root.now) {
            root.override = null;
            root.save();
        }
    }
    property Timer ticker: Timer {
        running: true
        repeat: true
        interval: root.ramping ? 15000 : 60000
        onTriggered: root.tick()
    }

    property bool alive: true
    property Process helper: Process {
        id: helper
        running: root.alive
        command: ["python3", `${Quickshell.shellDir}/scripts/nightlight/gammad.py`]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                const sp = line.indexOf(" ");
                const word = sp < 0 ? line : line.slice(0, sp);
                const arg = sp < 0 ? "" : line.slice(sp + 1);
                if (word === "ready") {
                    root.available = true;
                    root.failed = [];
                    root.lastSent = "";
                    root.push(root.cfg.fadeMs);
                } else if (word === "outputs") {
                    root.outputs = arg ? arg.split(",") : [];
                    root.failed = root.failed.filter(n => root.outputs.includes(n));
                } else if (word === "failed") {
                    if (!root.failed.includes(arg))
                        root.failed = root.failed.concat([arg]);
                } else if (word === "unsupported") {
                    root.available = false;
                }
            }
        }
        stderr: SplitParser {
            onRead: line => console.info(line)
        }
        // 3 = no wlr-gamma-control (stays off); else died → respawn.
        onExited: code => {
            root.lastSent = "";
            if (code === 3) {
                console.warn("[NightLight] the compositor has no wlr-gamma-control");
                root.available = false;
                return;
            }
            console.warn("[NightLight] gamma helper exited:", code);
            root.alive = false;
            respawn.restart();
        }
    }
    property Timer respawn: Timer {
        interval: 5000
        onTriggered: root.alive = true
    }

    // --- state ----------------------------------------------------------

    function save(): void {
        stateFile.write({ manualOn: root.manualOn, override: root.override, lat: root.lat, lon: root.lon });
    }
    property StateFile stateFile: StateFile {
        name: "nightlight.json"
        onLoaded: {
            const s = stateFile.read();
            root.manualOn = s.manualOn === true;
            const o = s.override;
            root.override = o && typeof o.until === "number" && o.until > Date.now() ? { on: o.on === true, until: o.until } : null;
            if (typeof s.lat === "number" && typeof s.lon === "number") {
                root.lat = s.lat;
                root.lon = s.lon;
            }
            root.takeLocation();
        }
    }

    property IpcHandler ipc: IpcHandler {
        target: "nightlight"
        function toggle(): void { root.toggle(); }
        function on(): void { root.setActive(true); }
        function off(): void { root.setActive(false); }
        function preview(kelvin: int): void { root.preview(kelvin); }
        function status(): string {
            return JSON.stringify({
                available: root.available, active: root.active, kelvin: root.kelvin, level: root.level,
                mode: root.mode, sunFallback: root.sunFallback, override: root.override,
                sunrise: root.hm(root.sunrise), sunset: root.hm(root.sunset),
                outputs: root.outputs, failed: root.failed, status: root.status
            });
        }
    }
}
