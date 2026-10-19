import QtQuick
import "../components"
import "../components/Graphemes.js" as Graphemes

// Event indicator, RIGHT half: the text of the visible event at the far
// right of the bar row (EventIcon = left half). Texts may be functions:
// they are called inside the binding, so live values (time to full,
// headphone battery) update while the event shows. `texts: [a, b, ...]`
// = steps: every `events.textStepMs` the next one drum-rolls in
// (RollingText), e.g. charging: percent -> time to full. Width = per-char
// advances (RollingText lays out one slot per character; its own width
// springs and must not feed back here), of the WIDEST step, latched per
// event; capped at eventTextMaxWidth. The label stays right-aligned.
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
    // A NEW event (out of the gap or another key) resets the latched width;
    // an in-place update of the same key keeps it.
    property bool hadLive: false
    onLiveChanged: {
        if (live) {
            const fresh = !hadLive || (ev?.key ?? "") !== (live.key ?? "");
            ev = live;
            step = 0;
            if (fresh)
                peak = stepsMax;
        }
        hadLive = live !== null;
    }
    property bool entered: false
    Component.onCompleted: {
        ev = live;
        hadLive = live !== null;
        peak = stepsMax;
        entered = true;
    }

    // Theme colour name (a function = live): `textColor`, else neutral
    // Theme.eventText — only the glyph carries the event `color`.
    readonly property string toneName: {
        const c = root.ev?.textColor ?? "eventText";
        return typeof c === "function" ? `${c()}` : `${c}`;
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

    function widthOf(str: string): real {
        let w = 0;
        for (const ch of Graphemes.split(str))
            w += fm.advanceWidth(ch);
        return Math.ceil(Math.min(cfg?.eventTextMaxWidth ?? 120, w));
    }
    readonly property real textWidth: root.widthOf(root.value)
    // The slot is sized ONCE per event (user: the island must not resize
    // after it has spread, e.g. when the text rolls from "95%" to "1 h 25
    // min"): the widest of ALL steps, latched — it may only grow (a live
    // value getting longer), never shrink, until the next event.
    readonly property real stepsMax: {
        let w = 0;
        for (const t of root.steps)
            w = Math.max(w, root.widthOf(typeof t === "function" ? `${t()}` : `${t ?? ""}`));
        return w;
    }
    // Latched in a handler of stepsMax (not of slotWidth itself — writing
    // the latch from slotWidth's own change handler was a binding loop).
    property real peak: 0
    onStepsMaxChanged: if (root.stepsMax > root.peak) root.peak = root.stepsMax
    readonly property real slotWidth: root.peak
    // Extra distance from the rest of the row (on top of the row spacing).
    readonly property real gap: cfg?.eventGap ?? 28
    // A status's event (IndicatorLayout): the text follows the glyph on the
    // left (the right end holds the inline ring) — left-aligned, the gap
    // toward the row on its right.
    property bool leading: false
    readonly property real desiredWidth: active ? slotWidth + gap : 0

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
        anchors.right: root.leading ? undefined : parent.right
        anchors.left: root.leading ? parent.left : undefined
        width: root.textWidth + 2
        height: parent.height
        shown: root.active && !root.evicted

        RollingText {
            id: label
            anchors.right: root.leading ? undefined : parent.right
            anchors.left: root.leading ? parent.left : undefined
            anchors.verticalCenter: parent.verticalCenter
            text: root.value
            // Neutral (Theme.eventText) unless the event sets `textColor`.
            color: root.theme?.[root.toneName] ?? root.theme?.islandFg ?? "#E9ECF1"
            pixelSize: root.theme?.fontSizeClock ?? 14
            weight: Font.Medium
            family: root.theme?.fontFamily ?? "SF Pro Display"
        }
    }
}
