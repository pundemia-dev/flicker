import QtQuick
import "../../components"
import "../../config"

// Timer module (services/Countdown). Two layouts, ONE driver `k` (spring,
// 0 = setup, 1 = live) moving every element together:
//  - setup: minute ruler (TimerRuler) on top, start button bottom-left,
//    the chosen time bottom-right (rolling digits);
//  - live (running / paused / done): the time in the centre (the setup
//    time flies there), pause left, cancel ✕ right, "🔔 HH:mm" above,
//    "Timer" below, the remaining time as a progress along the island's
//    perimeter.
// Shared slots (core/TransitionLayer): "time" (the bar clock flies in and
// hides; the module rolls its own digits) and "perimeter" (the bar ring
// unfolds into the outline). Without a docked element the module draws
// both itself.
// Keys: ←/→ ±1 min (Shift ±5), ↑/↓ ±5, Home/End, Enter/Space start or
// pause, Delete cancel, Esc close.
Item {
    id: root
    required property var countdown
    property var theme: null
    property var haptics: null
    property var cfg: null
    property real surfaceRadius: 0
    signal closeRequested

    readonly property bool live: root.countdown.active
    readonly property string phase: root.countdown.phase
    readonly property real pad: root.cfg.padding ?? 18
    readonly property real bs: root.cfg.buttonSize ?? 52
    // Live layout (pause / cancel): bigger buttons, further from the edge
    // (clear of the perimeter progress).
    readonly property real liveBs: root.cfg.liveButtonSize ?? 62
    readonly property real livePad: root.cfg.livePadding ?? 32
    readonly property real liveSize: root.cfg.liveTimeSize ?? 46
    readonly property real setupScale: (root.cfg.setupTimeSize ?? 30) / root.liveSize

    function sharedSlot(key: string): var {
        return key === "time" ? timeSlot : key === "perimeter" ? perimeterSlot : null;
    }

    // Layout driver: everything lerps between the two layouts on it.
    property real k: root.live ? 1 : 0
    Behavior on k { Spring { stiffness: root.cfg.layoutStiffness ?? 3.5; damp: root.cfg.layoutDamping ?? 0.5; eps: 0.002 } }
    function mixv(a: real, b: real): real {
        return a + (b - a) * root.k;
    }

    function startOrToggle(): void {
        if (!root.live)
            root.countdown.start(ruler.selected);
        else
            root.countdown.toggle();
    }
    function cancel(): void {
        const wasDone = root.phase === "done";
        root.countdown.cancel();
        if (wasDone)
            root.closeRequested();
    }

    focus: true
    Component.onCompleted: root.forceActiveFocus()
    Keys.onEscapePressed: root.closeRequested()
    Keys.onPressed: event => {
        const k = event.key, shift = event.modifiers & Qt.ShiftModifier;
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space)
            root.startOrToggle();
        else if (k === Qt.Key_Delete || k === Qt.Key_Backspace)
            root.live ? root.cancel() : ruler.select(0);
        else if (root.live)
            return;
        else if (k === Qt.Key_Left || k === Qt.Key_Right)
            ruler.step((k === Qt.Key_Left ? -1 : 1) * (shift ? 5 : 1), event.isAutoRepeat);
        else if (k === Qt.Key_Up || k === Qt.Key_Down)
            ruler.step(k === Qt.Key_Down ? -5 : 5, event.isAutoRepeat);
        else if (k === Qt.Key_Home)
            ruler.select(0);
        else if (k === Qt.Key_End)
            ruler.select(ruler.maxMinutes);
        else
            return;
        event.accepted = true;
    }

    // ---- perimeter progress (slot "perimeter")

    Item {
        id: perimeterSlot
        // Gap from the island edge = the line's own width (user).
        readonly property real inset: perimeterSlot.lineWidth
        x: inset
        y: inset
        width: root.width - 2 * inset
        height: root.height - 2 * inset
        // Targets for the flying ring (contract: radius, lineWidth).
        readonly property real radius: Math.max(0, root.surfaceRadius - inset)
        readonly property real lineWidth: root.cfg.perimeterLine ?? 8
        // Open at the top: a centred gap of `perimeterGap` of the island
        // width (user: a third).
        readonly property real gap: root.width * (root.cfg.perimeterGap ?? 1 / 3)
        property Item docked: null

        PerimeterProgress {
            id: ownPerimeter
            anchors.fill: parent
            visible: perimeterSlot.docked === null
            radius: perimeterSlot.radius
            lineWidth: perimeterSlot.lineWidth
            gap: perimeterSlot.gap
            progress: root.countdown.progress
            color: root.phase === "paused" ? (root.theme?.timerPaused ?? "#8E8E93") : (root.theme?.timerAccent ?? "#FF9F0A")
            readonly property color track: root.theme?.timerTrack ?? "#33FFFFFF"
            trackColor: Qt.rgba(track.r, track.g, track.b, track.a * Math.max(0, Math.min(1, reveal)))
            // Draws in on start, un-draws on cancel.
            reveal: root.live ? 1 : 0
            Behavior on reveal { Spring { stiffness: 2.5; damp: 0.65; eps: 0.002 } }
        }
    }

    // ---- setup: ruler

    FadeBlur {
        shown: !root.live
        x: root.pad
        // Placed by the triangle: its top sits triangleOffset below the
        // module's vertical centre (user: pointer below the middle).
        y: root.height / 2 + (root.cfg.triangleOffset ?? 6) - ruler.triTop
        width: root.width - 2 * root.pad
        height: ruler.implicitHeight

        TimerRuler {
            id: ruler
            anchors.fill: parent
            cfg: root.cfg
            countdown: root.countdown
            theme: root.theme
            haptics: root.haptics
        }
    }

    // ---- live: "🔔 HH:mm" above the time, "Timer" below

    readonly property real liveCy: root.height / 2 + (root.cfg.liveTimeOffset ?? 2)
    FadeBlur {
        shown: root.live
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.liveCy - root.liveSize * 0.62 - height - (root.cfg.liveLabelGap ?? 2)
        width: bellRow.implicitWidth
        height: bellRow.implicitHeight

        Row {
            id: bellRow
            spacing: 5
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.phase === "done" ? "" : "" // bell-ringing / bell (filled)
                color: root.phase === "done" ? (root.theme?.timerAccent ?? "#FF9F0A") : (root.theme?.timerDim ?? "#8E8E93")
                font.family: root.theme?.iconFamily ?? "tabler-icons"
                font.pixelSize: root.cfg.smallSize ?? 15
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.countdown.endText
                color: root.theme?.timerDim ?? "#8E8E93"
                font.family: root.theme?.fontFamily ?? "SF Pro Display"
                font.pixelSize: root.cfg.smallSize ?? 15
                font.weight: Font.Medium
                font.features: { "tnum": 1 }
            }
        }
    }
    FadeBlur {
        shown: root.live
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.liveCy + root.liveSize * 0.62 + (root.cfg.liveLabelGap ?? 2)
        width: timerLabel.implicitWidth
        height: timerLabel.implicitHeight
        Text {
            id: timerLabel
            text: I18n.tr("Timer")
            color: root.theme?.timerDim ?? "#8E8E93"
            font.family: root.theme?.fontFamily ?? "SF Pro Display"
            font.pixelSize: root.cfg.smallSize ?? 15
            font.weight: Font.Medium
        }
    }

    // ---- the time (slot "time"): bottom-right in setup, centre when live

    Item {
        id: timeSlot
        property Item docked: null
        // Live: full size, shrunk to fit between the buttons ("1:04:59").
        // (clamped: while the module is still narrow the fit goes negative)
        readonly property real fit: Math.max(root.setupScale, Math.min(1, (root.width - 2 * (root.livePad + root.liveBs + (root.cfg.liveTimeGap ?? 10))) / Math.max(1, roll.implicitWidth)))
        readonly property real s: root.setupScale + (timeSlot.fit - root.setupScale) * root.k
        // Targets for the flying clock (contract).
        readonly property string text: roll.text
        readonly property color color: roll.color
        readonly property font font: Qt.font({
                family: roll.family,
                pixelSize: roll.pixelSize * timeSlot.s,
                weight: roll.weight
            })

        width: roll.implicitWidth * s
        height: roll.implicitHeight * s
        x: root.mixv(root.width - root.pad - width, (root.width - width) / 2)
        y: root.mixv(root.height - root.pad - root.bs / 2, root.liveCy) - height / 2

        RollingText {
            id: roll
            transformOrigin: Item.TopLeft
            scale: timeSlot.s
            // Hidden while the clock flies in (landed = it hides itself).
            visible: timeSlot.docked === null || timeSlot.docked.parent === timeSlot
            text: root.live ? root.countdown.remainingText : root.countdown.format(ruler.centreIndex * 60)
            color: root.phase === "done" ? (root.theme?.timerAccent ?? "#FF9F0A") : (root.theme?.islandFg ?? "#E9ECF1")
            family: root.theme?.fontFamily ?? "SF Pro Display"
            pixelSize: root.liveSize
            weight: Font.DemiBold
            // Drawn at liveSize and scaled (setup ≈ 0.65): NativeRendering
            // glyphs hinted at 46 px came out distorted once scaled down.
            renderType: Text.CurveRendering
        }
    }

    // ---- buttons: start → pause/resume (one button moving), cancel ✕

    TimerButton {
        id: mainBtn
        size: root.live ? root.liveBs : root.bs
        x: root.mixv(root.pad, root.livePad)
        y: root.mixv(root.height - root.pad - root.bs, (root.height - root.liveBs) / 2)
        family: root.theme?.iconFamily ?? "tabler-icons"
        glyphSize: root.live ? (root.cfg.liveGlyphSize ?? 30) : (root.cfg.glyphSize ?? 22)
        // Setup: a "Start timer" pill (user); live: the pause / resume /
        // restart disc.
        label: root.live ? "" : I18n.tr("Start timer")
        labelFamily: root.theme?.fontFamily ?? "SF Pro Display"
        labelSize: root.cfg.startLabelSize ?? 15
        glyph: !root.live ? "" : root.phase === "paused" ? "\uf691" : root.phase === "done" ? "\ueb13" : "\uf690"
        disc: root.live ? (root.theme?.timerButton ?? "#3A3A3C") : (root.theme?.timerStartDisc ?? "#3D2A0A")
        ink: root.live ? (root.theme?.islandFg ?? "#FFFFFF") : (root.theme?.timerAccent ?? "#FF9F0A")
        enabledState: root.live || ruler.selected > 0
        onClicked: root.startOrToggle()
    }
    TimerButton {
        size: root.liveBs
        x: root.width - root.livePad - root.liveBs
        y: (root.height - root.liveBs) / 2
        cross: true
        glyphSize: root.cfg.liveGlyphSize ?? 30
        disc: root.theme?.timerCancelDisc ?? "#4A1A17"
        ink: root.theme?.timerCancelInk ?? "#FF453A"
        appear: root.k
        enabled: root.live
        onClicked: root.cancel()
    }
}
