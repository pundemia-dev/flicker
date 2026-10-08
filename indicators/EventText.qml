import QtQuick
import "../components"

// Event indicator, RIGHT half: the text of the visible event at the far
// right of the bar row (EventIcon = left half). Texts may be functions:
// they are called inside the binding, so live values (time to full,
// headphone battery) update while the event shows. `texts: [a, b, ...]`
// = steps: every `events.textStepMs` the next one drum-rolls in
// (RollingText), e.g. charging: percent -> time to full. Width = the sum of
// per-character advances of the TARGET text (RollingText lays out one slot
// per character; its own width springs and must not feed back here),
// capped at eventTextMaxWidth.
Item {
    id: root
    property var services: null
    property bool evicted: false

    readonly property var events: services?.events ?? null
    readonly property var theme: services?.theme ?? null
    readonly property var cfg: services?.cfg ?? null
    readonly property var live: events?.current ?? null
    readonly property bool active: live !== null
    property var ev: null
    property int step: 0
    onLiveChanged: if (live) {
        ev = live;
        step = 0;
    }
    property bool entered: false
    Component.onCompleted: {
        ev = live;
        entered = true;
    }

    readonly property var steps: root.ev?.texts ?? [root.ev?.text ?? ""]
    readonly property string value: {
        const t = root.steps[Math.min(root.step, root.steps.length - 1)] ?? "";
        return typeof t === "function" ? `${t()}` : `${t}`;
    }
    Timer {
        interval: root.events?.cfg?.textStepMs ?? 1800
        running: root.active && root.step < root.steps.length - 1
        onTriggered: root.step++
    }

    readonly property real textWidth: {
        let w = 0;
        for (const ch of root.value)
            w += fm.advanceWidth(ch);
        return Math.ceil(Math.min(cfg?.eventTextMaxWidth ?? 120, w));
    }
    // Extra distance from the rest of the row (on top of the row spacing).
    readonly property real gap: cfg?.eventGap ?? 48
    readonly property real desiredWidth: active ? textWidth + gap : 0

    width: (entered && !evicted) ? desiredWidth : 0
    height: cfg?.musicCoverDiameter ?? 24
    Behavior on width { Spring {} }

    FontMetrics {
        id: fm
        font.family: label.family
        font.pixelSize: label.pixelSize
        font.weight: label.weight
        font.features: { "tnum": 1 }
    }

    FadeBlur {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        width: root.textWidth + 2
        height: parent.height
        shown: root.active && !root.evicted

        RollingText {
            id: label
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.value
            // Tinted like the glyph (event `textColor`, else its `color`).
            color: root.theme?.[root.ev?.textColor ?? root.ev?.color ?? "islandFg"] ?? root.theme?.islandFg ?? "#E9ECF1"
            pixelSize: root.theme?.fontSizeClock ?? 14
            weight: Font.Medium
            family: root.theme?.fontFamily ?? "SF Pro Display"
        }
    }
}
