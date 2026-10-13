import QtQuick
import "../components"

// The timer's ring in the bar (components/PerimeterProgress) as a shared-
// element owner (core/TransitionLayer): it unfolds into the timer module's
// perimeter on open and folds back here on close. Worn by the stand-alone
// timer indicator (TimerRing) or around the music cover (Music) while a
// player shows. Square box; `shown` draws it in / out.
Item {
    id: root
    property var countdown: null
    property var theme: null
    property real line: 2.5
    property bool shown: true

    // Shared element contract: box, radius, stroke width and the top gap
    // morph (ring <-> outline with a free top third).
    readonly property Item sharedElement: ring
    readonly property var sharedTransition: ({
            target: "timer",
            slot: "perimeter",
            properties: { radius: "slot", lineWidth: "slot", gap: "slot" },
            curve: "spring"
        })
    readonly property Item sharedHome: root
    function restoreShared(): void {
        ring.anchors.fill = root;
        ring.radius = Qt.binding(() => root.width / 2);
        ring.lineWidth = Qt.binding(() => root.line);
        ring.gap = 0;
    }

    PerimeterProgress {
        id: ring
        anchors.fill: parent
        radius: root.width / 2
        lineWidth: root.line
        progress: root.countdown?.progress ?? 0
        color: root.countdown?.phase === "paused" ? (root.theme?.timerPaused ?? "#8E8E93") : (root.theme?.timerAccent ?? "#FF9F0A")
        readonly property color track: root.theme?.timerTrack ?? "#33FFFFFF"
        trackColor: Qt.rgba(track.r, track.g, track.b, track.a * Math.max(0, Math.min(1, reveal)))
        // Draws in from the top when shown, out when hidden.
        property bool started: false
        Component.onCompleted: started = true
        reveal: started && root.shown ? 1 : 0
        Behavior on reveal { Spring { stiffness: 3; damp: 0.6; eps: 0.002 } }
    }
}
