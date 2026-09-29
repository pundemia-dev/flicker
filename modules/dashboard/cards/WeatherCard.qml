import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../components"

// Weather card: city top-left, big degrees bottom-left; icon top-right,
// description + day min/max below it. The card body is a bottom-to-top
// gradient whose colors encode weather + sun geometry (exact rule below),
// animated on change instead of snapping.
//
// EXACT GRADIENT RULE — two continuous numbers, no phases.
// t = location-local minutes of day, sr/ss = sunrise/sunset in minutes,
// S(x) = smoothstep clamped to [0..1], T = 45, G = 60.
// 1. daylight d in [0..1] = S((t-(sr-T))/2T) * (1 - S((t-(ss-T))/2T)).
//    0 at night, 1 in the middle of the day, exactly 0.5 at sr and ss.
// 2. horizon glow w in [0..1] = S(max(0, 1-|t-sr|/G, 1-|t-ss|/G)).
//    Peak exactly at sr/ss, gone G minutes either way.
// 3. Palettes {b: bottom, t: top} per WMO category: Day (basePal) and
//    Night (nightPal).
// 4. base_x = mix(Night[c].x, Day[c].x, d); k = w * cloudDamp[c]
//    top    = mix(base_t, #6C5B9E, 0.25*k)   // dusk violet up top
//    bottom = mix(base_b, #F29A5B, 0.8*k)    // warm glow at the horizon
// 5. cloudDamp (clouds eat the glow): clear 1, cloudy 0.5, snow 0.4,
//    fog 0.35, rain 0.3, storm 0.15, unknown 0.5.
// 6. No sun data: d = isDay ? 1 : 0, w = 0.
// Day palettes: clear #2F9BFF/#0F7CEC, cloudy #3A3F48/#6E7681,
// fog #41464E/#2B2F36, rain #33506B/#1B2836, snow #5E86A8/#8FA9C4,
// storm #2E3440/#12141A.
DashboardCard {
    id: root
    required property var weather
    required property var clock

    readonly property int spanCols: 4
    readonly property int spanRows: 1

    color: "transparent"

    readonly property bool ok: (weather?.available) ?? false
    readonly property real _pad: (dash?.cardPadding) ?? 10
    readonly property real _innerH: root.height - 2 * _pad
    readonly property real _tempFs: Math.max(24, Math.min(42, _innerH - 18))
    // Right column width, single-sourced: the city bound below derives
    // from it, so the arrow always glues to the text.
    readonly property real _rightW: 132
    readonly property real _descFs: (dash?.titleSize) ?? 13
    readonly property real _mmFs: Math.max(10, ((dash?.titleSize) ?? 13) - 1)

    function fmt(c: real): string {
        if (c === null || c === undefined || isNaN(c))
            return "—";
        const fahr = (root.dash?.useFahrenheit) ?? false;
        return `${Math.round(fahr ? c * 9 / 5 + 32 : c)}°`;
    }

    function minsOf(s: string): int {
        const p = (s ?? "").split(":");
        return p.length === 2 ? (+p[0]) * 60 + (+p[1]) : -1;
    }

    function category(code: int): string {
        if (code === 0 || code === 1)
            return "clear";
        if (code === 2 || code === 3)
            return "cloudy";
        if (code === 45 || code === 48)
            return "fog";
        if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82))
            return "rain";
        if (code >= 71 && code <= 77)
            return "snow";
        if (code >= 95)
            return "storm";
        return "unknown";
    }

    function basePal(cat: string): var {
        if (cat === "clear")
            return { b: "#2F9BFF", t: "#0F7CEC" };
        if (cat === "cloudy")
            return { b: "#3A3F48", t: "#6E7681" };
        if (cat === "fog")
            return { b: "#41464E", t: "#2B2F36" };
        if (cat === "rain")
            return { b: "#33506B", t: "#1B2836" };
        if (cat === "snow")
            return { b: "#5E86A8", t: "#8FA9C4" };
        if (cat === "storm")
            return { b: "#2E3440", t: "#12141A" };
        return { b: "#2C2C2E", t: "#1C1C1E" };
    }

    function mix(a: string, b: string, t: real): string {
        const pa = [1, 3, 5].map(i => parseInt(a.substr(i, 2), 16));
        const pb = [1, 3, 5].map(i => parseInt(b.substr(i, 2), 16));
        const q = pa.map((v, i) => Math.max(0, Math.min(255, Math.round(v + (pb[i] - v) * t))));
        return "#" + q.map(v => v.toString(16).padStart(2, "0")).join("");
    }

    // Night palettes {b: bottom, t: top}; top is darker.
    function nightPal(cat: string): var {
        if (cat === "clear")
            return { b: "#16305A", t: "#060D1A" };
        if (cat === "cloudy")
            return { b: "#232B38", t: "#0E1219" };
        if (cat === "fog")
            return { b: "#262B33", t: "#14171C" };
        if (cat === "rain")
            return { b: "#1A2B3F", t: "#0A121C" };
        if (cat === "snow")
            return { b: "#2E4159", t: "#182231" };
        if (cat === "storm")
            return { b: "#1B1F27", t: "#08090D" };
        return { b: "#1C1C1E", t: "#0A0A0B" };
    }

    // How much clouds suppress the horizon glow.
    function cloudDamp(cat: string): real {
        const m = { clear: 1.0, cloudy: 0.5, snow: 0.4, fog: 0.35, rain: 0.3, storm: 0.15 };
        return m[cat] ?? 0.5;
    }

    function smooth(x: real): real {
        const c = Math.max(0, Math.min(1, x));
        return c * c * (3 - 2 * c);
    }

    // Location-local minutes of day (whole minutes: gradient updates once/min).
    readonly property int nowMin: {
        const tick = ((clock?.date)?.getTime()) ?? Date.now();
        const s = Math.floor(tick / 1000 + ((weather?.utcOffset) ?? 0));
        return Math.floor((((s % 86400) + 86400) % 86400) / 60);
    }

    // {d: daylight 0..1, w: horizon glow 0..1}
    readonly property var sun: {
        const sr = root.minsOf(weather?.sunrise ?? "");
        let ss = root.minsOf(weather?.sunset ?? "");
        if (sr < 0 || ss < 0)
            return { d: ((weather?.isDay) ?? true) ? 1 : 0, w: 0 };
        if (ss < sr)
            ss += 1440;                       // sunset after local midnight
        let t = root.nowMin;
        const mid = (sr + ss) / 2;            // put t on the same "day" as the sun
        if (t - mid > 720)
            t -= 1440;
        else if (mid - t > 720)
            t += 1440;
        const T = 45, G = 60;
        const d = root.smooth((t - (sr - T)) / (2 * T)) * (1 - root.smooth((t - (ss - T)) / (2 * T)));
        const g = Math.max(0, 1 - Math.abs(t - sr) / G, 1 - Math.abs(t - ss) / G);
        return { d: d, w: root.smooth(g) };
    }

    // Animated gradient endpoints: plain (writable) props fed by
    // updateGradient() — Behavior cannot attach to readonly properties.
    property color topColor: "#0F7CEC"
    property color bottomColor: "#2F9BFF"

    Behavior on topColor { ColorAnimation { duration: 900; easing.type: Easing.InOutQuad } }
    Behavior on bottomColor { ColorAnimation { duration: 900; easing.type: Easing.InOutQuad } }

    function updateGradient(): void {
        const cat = root.ok ? root.category((weather?.weatherCode) ?? -1) : "unknown";
        const day = basePal(cat), night = nightPal(cat);
        const d = root.sun.d;
        const k = root.cloudDamp(cat) * root.sun.w;
        topColor = mix(mix(night.t, day.t, d), "#6C5B9E", 0.25 * k);
        bottomColor = mix(mix(night.b, day.b, d), "#F29A5B", 0.8 * k);
    }

    Component.onCompleted: root.updateGradient()
    onSunChanged: root.updateGradient()

    Connections {
        target: root.weather
        function onAvailableChanged(): void { root.updateGradient(); }
        function onWeatherCodeChanged(): void { root.updateGradient(); }
    }

    // Emoji icons (Noto Color Emoji is installed; pShell's tabler PUA
    // glyphs are unavailable here). Day/night variants for clear skies.
    // Fallback only — primary icons are meteocons AnimatedImages below.
    function iconEmojiFor(code: int, day: bool): string {
        if (code === 0)
            return day ? "☀️" : "🌙";
        if (code === 1)
            return day ? "🌤️" : "🌙";
        if (code === 2)
            return "⛅️";
        if (code === 3)
            return "☁️";
        if (code === 45 || code === 48)
            return "🌫️";
        if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82))
            return "🌧️";
        if (code >= 71 && code <= 77)
            return "🌨️";
        if (code >= 95)
            return "⛈️";
        return "";
    }

    // Meteocons fill (MIT, vendored in assets/weather/ as animated WebP —
    // Qt plays neither SMIL nor Lottie). Converted offline from Lottie via
    // python-lottie + cairosvg (see convert.py in /tmp, not vendored).
    function iconFileFor(code: int, day: bool): string {
        if (code === 0)
            return day ? "clear-day" : "clear-night";
        if (code === 1)
            return day ? "mostly-clear-day" : "mostly-clear-night";
        if (code === 2)
            return day ? "partly-cloudy-day" : "partly-cloudy-night";
        if (code === 3)
            return "overcast";
        if (code === 45 || code === 48)
            return "fog";
        if (code >= 51 && code <= 57)
            return "drizzle";
        if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82))
            return "rain";
        if (code >= 71 && code <= 77)
            return "snow";
        if (code >= 95)
            return "thunderstorms";
        return "not-available";
    }

    readonly property string tempStr: root.ok ? root.fmt(weather.tempC) : "—"
    readonly property string cityStr: (weather?.city) ?? ""
    readonly property string descStr: root.ok ? (weather.desc || "") : "Нет данных"
    readonly property string iconEmoji: root.ok ? root.iconEmojiFor((weather?.weatherCode) ?? -1, root.sun.d > 0.5) : ""
    readonly property string iconFile: {
        if (!root.ok)
            return "";
        // Absolute file:// URL: quickshell rewrites file URLs through its
        // qs:@ interceptor, where a relative path resolves nowhere and the
        // image hangs in Loading forever (never errors, never plays).
        const name = root.iconFileFor((weather?.weatherCode) ?? -1, root.sun.d > 0.5);
        return `file://${Quickshell.shellDir}/assets/weather/${name}.webp`;
    }
    readonly property real _iconSize: (dash?.iconSize) ?? 24
    readonly property string mmStr: root.ok ? `↓ ${root.fmt(weather.tempMinC)} · ↑ ${root.fmt(weather.tempMaxC)}` : "—"

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0; color: root.topColor }
            GradientStop { position: 1; color: root.bottomColor }
        }
    }

    // Anchors, not a RowLayout: the layout's stretch pass left the right
    // column short of the edge (left column kept its implicit width, so
    // the zone ended 90px early). Anchors pin it flush right.
    Item {
        anchors.fill: parent
        anchors.margins: root._pad

        ColumnLayout {
            id: leftCol
            anchors.left: parent.left
            anchors.right: rightZone.left
            anchors.rightMargin: 10
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                spacing: 0

                // No fillWidth: the city hugs its text so the arrow glues
                // to the last glyph. Long names elide.
                Text {
                    text: root.cityStr
                    color: root.theme?.cardDim ?? "#99EBEBF5"
                    font.pixelSize: root._descFs
                    elide: Text.ElideRight
                    Layout.maximumWidth: leftCol.width - 16
                }
                Text {
                    // Map-navigation cursor: base arrow rotated NE.
                    text: "➤"
                    rotation: -45
                    color: root.theme?.cardDim ?? "#99EBEBF5"
                    font.pixelSize: root._descFs
                }
            }
            Item { Layout.fillHeight: true }
            Text {
                text: root.tempStr
                color: "white"
                font.pixelSize: root._tempFs
                font.weight: Font.DemiBold
                // Digits have no descenders: fixed leading lets the
                // temperature fill the leftover height exactly.
                lineHeight: 1.0
                lineHeightMode: Text.FixedHeight
            }
        }

        // Right zone: icon on top, description + min/max packed at the
        // bottom (the gap lives after the icon). The 1-row card is 60px
        // tall inside, so the icon size is capped by what is left for the
        // two text lines (config.dashboard.iconSize).
        ColumnLayout {
            id: rightZone
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: root._rightW
            spacing: 2

            Item {
                Layout.preferredWidth: root._iconSize
                Layout.preferredHeight: root._iconSize
                Layout.alignment: Qt.AlignRight

                AnimatedImage {
                    id: iconAnim
                    anchors.fill: parent
                    source: root.iconFile
                    playing: true
                    asynchronous: true
                    visible: root.iconFile !== "" && status !== AnimatedImage.Error
                }
                Text {
                    anchors.centerIn: parent
                    text: root.iconEmoji
                    font.pixelSize: 20
                    visible: !iconAnim.visible
                }
            }
            Item { Layout.fillHeight: true }
            Text {
                text: root.descStr
                color: root.theme?.cardDim ?? "#99EBEBF5"
                font.pixelSize: root._descFs
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignRight
                Layout.fillWidth: true
            }
            Text {
                text: root.mmStr
                color: "white"
                font.pixelSize: root._mmFs
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            // Bottom air: arrow tips reach the line bottom while digit
            // bottoms sit on the baseline, so without this the min/max
            // row reads tighter to the edge than the temperature does.
            // 2px, not 4: the 1-row card has no slack left.
            Item { height: 2 }
        }
    }
}
