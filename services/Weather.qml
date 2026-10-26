import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Weather via open-meteo (no API key), pShell Weather pattern: plain
// `curl -4` fetches (Qt stalls ~40s on IPv6 before falling back on an
// IPv4-only host). Location from Config.dashboard.weatherLocation:
// "" = auto by IP, "City" name, or "lat,lon". Offline = available false,
// cards render their empty state.
Item {
    id: root

    property bool available: false
    property string city: ""
    property int weatherCode: -1
    property real tempC: NaN
    property real tempMinC: NaN
    property real tempMaxC: NaN
    property string desc: ""
    property int humidity: 0
    property real windSpeed: 0
    // "HH:MM" local time from open-meteo daily (WeatherCard gradient rule).
    property string sunrise: ""
    property string sunset: ""
    property bool isDay: true
    // Location UTC offset, s (open-meteo root field): the gradient uses the
    // LOCATION clock (utc now + offset), not the viewer clock — they differ
    // for a configured remote city. Defaults to the system zone.
    property int utcOffset: -new Date().getTimezoneOffset() * 60

    property string _loc: ""
    // Resolved coordinates (NaN before the first lookup; NightLight's sun
    // schedule reads them and keeps its own copy for offline starts).
    readonly property real latitude: root._loc.indexOf(",") !== -1 ? parseFloat(root._loc.split(",")[0]) : NaN
    readonly property real longitude: root._loc.indexOf(",") !== -1 ? parseFloat(root._loc.split(",")[1]) : NaN
    property string _resolvedKey: ""

    readonly property string _wanted: Config.data.dashboard.weatherLocation ?? ""
    readonly property int pollMs: Config.data.dashboard.weatherPollMs ?? 1800000

    Timer {
        interval: root.pollMs
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.reload()
    }

    on_WantedChanged: root.reload()
    // The geocoded city name comes in the UI language: re-resolve on a switch.
    readonly property string _lang: I18n.lang
    on_LangChanged: root.reload()

    // Cache key of the resolved location: config value + name language.
    function _key(): string {
        return `${(root._wanted ?? "").trim()}|${root._lang}`;
    }

    function reload(): void {
        const cfg = (root._wanted ?? "").trim();
        if (root._resolvedKey === root._key() && root._loc.indexOf(",") !== -1) {
            root._fetch();
            return;
        }
        if (cfg && cfg.indexOf(",") !== -1 && !isNaN(parseFloat(cfg.split(",")[0]))) {
            root._resolvedKey = root._key();
            root._loc = cfg;
            root.city = "";
            root._fetch();
        } else if (cfg) {
            root._geocodeCity(cfg);
        } else {
            root._get("https://ipinfo.io/json", r => {
                const loc = r?.loc ?? "";
                if (loc.indexOf(",") !== -1) {
                    root._resolvedKey = root._key();
                    root._loc = loc;
                    root.city = r?.city ?? "";
                    root._fetch();
                }
            });
        }
    }

    function _geocodeCity(name: string): void {
        const key = root._key();
        root._get(`https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(name)}&count=1&language=${encodeURIComponent(root._lang || "en")}&format=json`, r => {
            const hit = r?.results?.[0] ?? null;
            if (hit) {
                root._resolvedKey = key;
                root._loc = `${hit.latitude},${hit.longitude}`;
                root.city = hit.name ?? name;
                root._fetch();
            }
        });
    }

    function _fetch(): void {
        const parts = root._loc.split(",");
        if (parts.length < 2)
            return;
        root._get(`https://api.open-meteo.com/v1/forecast?latitude=${parts[0]}&longitude=${parts[1]}&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m,is_day&daily=temperature_2m_max,temperature_2m_min,weather_code,sunrise,sunset&timezone=auto&forecast_days=1`, r => {
            const cur = r?.current ?? null;
            const daily = r?.daily ?? null;
            if (!cur)
                return;
            root.tempC = cur.temperature_2m ?? NaN;
            root.humidity = cur.relative_humidity_2m ?? 0;
            root.windSpeed = cur.wind_speed_10m ?? 0;
            root.weatherCode = cur.weather_code ?? -1;
            root.isDay = (cur.is_day ?? 1) === 1;
            root.desc = root.wmoDesc(root.weatherCode);
            if (typeof r?.utc_offset_seconds === "number")
                root.utcOffset = r.utc_offset_seconds;
            if (daily) {
                root.tempMaxC = daily.temperature_2m_max?.[0] ?? NaN;
                root.tempMinC = daily.temperature_2m_min?.[0] ?? NaN;
                root.sunrise = root.hm(daily.sunrise?.[0] ?? "");
                root.sunset = root.hm(daily.sunset?.[0] ?? "");
            }
            root.available = true;
        });
    }

    // "2026-09-28T06:12" -> "06:12".
    function hm(iso: string): string {
        return iso.length >= 16 ? iso.slice(11, 16) : "";
    }

    // English I18n keys; the card translates them (follows a language switch).
    function wmoDesc(code: int): string {
        if (code === 0)
            return "Clear";
        if (code >= 1 && code <= 3)
            return code === 1 ? "Mostly clear" : code === 2 ? "Partly cloudy" : "Overcast";
        if (code === 45 || code === 48)
            return "Fog";
        if (code >= 51 && code <= 57)
            return "Drizzle";
        if (code >= 61 && code <= 67)
            return "Rain";
        if (code >= 71 && code <= 77)
            return "Snow";
        if (code >= 80 && code <= 82)
            return "Showers";
        if (code >= 95)
            return "Thunderstorm";
        return "—";
    }

    function _get(url: string, cb: var): void {
        fetchComp.createObject(root, { _url: url, _cb: cb });
    }

    Component {
        id: fetchComp

        Process {
            id: proc

            required property string _url
            required property var _cb

            command: ["curl", "-4", "-fsS", "--max-time", "10", _url]
            running: true

            stdout: StdioCollector {
                onStreamFinished: {
                    if (text && text.trim().length) {
                        try {
                            proc._cb(JSON.parse(text));
                        } catch (e) {
                            console.warn("[Weather] parse:", e, proc._url);
                        }
                    }
                    proc.destroy();
                }
            }

            onExited: code => {
                if (code !== 0)
                    console.warn("[Weather] curl exit", code, proc._url);
            }
        }
    }
}
