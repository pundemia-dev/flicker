import QtQuick
import QtQuick.Shapes
import "../../components"
import "../../config"

// Minute ruler of the timer setup: equal orange ticks (one per minute, a
// number above every `labelEvery`-th), an equilateral triangle under the
// centre points at the chosen value. A tick arriving on the triangle
// flashes bright yellow and springs back after flashHoldMs. Motion = the wallpaper
// carousel's: `pos` springs to `selected`, the spring is picked by pace
// (cfg.speeds: single step / quick steps within speedWindowMs / auto-repeat
// and jumps); mouse wheel = vertical, one notch per minute; touchpad =
// horizontal (touchpadStep per minute, accelerated). Ticks fade out
// toward the ends (opacity per tick, no masks).
Item {
    id: root
    required property var cfg
    required property var countdown
    property var theme: null
    property var haptics: null

    readonly property int maxMinutes: root.cfg.maxMinutes ?? 120
    readonly property real spacing: root.cfg.tickSpacing ?? 9
    readonly property int labelEvery: root.cfg.labelEvery ?? 5

    property int selected: root.countdown.setupMinutes
    onSelectedChanged: root.countdown.setupMinutes = root.selected
    property real pos: root.selected
    property int speedLevel: 0
    readonly property var speed: (root.cfg.speeds ?? [])[root.speedLevel] ?? ({ stiffness: 4, damping: 0.45 })
    Behavior on pos {
        Spring {
            stiffness: root.speed.stiffness
            damp: root.speed.damping
            eps: 0.002
        }
    }
    // Value under the triangle right now (the rolling time follows it).
    readonly property int centreIndex: Math.max(0, Math.min(root.maxMinutes, Math.round(root.pos)))
    // Haptic detent per minute passing the triangle (Config.haptics.timer).
    // Only while the user moves it (a step within the last second): the
    // module's creation and an IPC start also move `pos` — no clicks there.
    onCentreIndexChanged: if ((Config.data.haptics?.timer ?? true) && Date.now() - root.lastStepAt < 1000)
        root.haptics?.click()

    property real lastStepAt: 0
    function step(n: int, fast: bool): void {
        if (n === 0)
            return;
        const now = Date.now();
        const quick = now - root.lastStepAt < (root.cfg.speedWindowMs ?? 280);
        root.lastStepAt = now;
        const top = Math.max(0, (root.cfg.speeds ?? []).length - 1);
        root.speedLevel = Math.min(top, fast || Math.abs(n) > 1 ? 2 : (quick ? Math.max(1, root.speedLevel) : 0));
        root.selected = Math.max(0, Math.min(root.maxMinutes, root.selected + n));
        root.pos = root.selected;
    }
    function select(i: int): void {
        root.step(i - root.selected, Math.abs(i - root.selected) > 1);
    }

    // Wheel accumulator (WallActions.wheel): one minute per `unit`.
    property real wheelAcc: 0
    function wheel(delta: real, unit: real): void {
        if (delta === 0)
            return;
        if (root.wheelAcc !== 0 && Math.sign(delta) !== Math.sign(root.wheelAcc))
            root.wheelAcc = 0;
        root.wheelAcc += delta;
        while (Math.abs(root.wheelAcc) >= unit) {
            const back = root.wheelAcc > 0;
            root.wheelAcc += back ? -unit : unit;
            root.step(back ? -1 : 1, false);
        }
    }
    property real touchpadAt: 0
    function touchpadGain(dx: real): real {
        const from = Math.max(1, root.cfg.touchpadAccelFrom ?? 30);
        const extra = Math.max(0, Math.abs(dx) - from) / from;
        return Math.min(root.cfg.touchpadAccelMax ?? 3, 1 + (root.cfg.touchpadAccel ?? 1) * extra);
    }

    // Vertical layout: numbers, ticks (bottom-aligned), triangle.
    readonly property real labelSize: root.cfg.labelSize ?? 12
    readonly property real tickH: root.cfg.tickHeight ?? 32
    readonly property real ticksBottom: root.labelSize + 6 + root.tickH
    readonly property color tickColor: root.theme?.timerAccent ?? "#FF9F0A"
    readonly property color flashColor: root.theme?.timerTickFlash ?? "#FFE14D"
    // Ticks right of the triangle (the time not chosen) are darker.
    readonly property color dimColor: root.theme?.timerTickDim ?? "#6B4307"
    function mixc(a: color, b: color, t: real): color {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1);
    }
    readonly property real tri: root.cfg.triangleSize ?? 12
    readonly property real triTop: root.ticksBottom + (root.cfg.triangleGap ?? 6)
    implicitHeight: root.triTop + root.tri * Math.sqrt(3) / 2

    readonly property real cx: root.width / 2
    // Ticks visible on each side; past fadeFrom of that they fade out.
    readonly property real half: root.width / 2 / root.spacing
    function fade(d: real): real {
        const from = root.half * (root.cfg.fadeFrom ?? 0.45);
        return Math.max(0, Math.min(1, 1 - (Math.abs(d) - from) / Math.max(1, root.half - from)));
    }

    Repeater {
        model: root.maxMinutes + 1
        delegate: Item {
            id: tick
            required property int index
            readonly property real d: tick.index - root.pos
            readonly property bool major: tick.index % root.labelEvery === 0
            readonly property real o: root.fade(tick.d)
            visible: tick.o > 0.01
            x: root.cx + tick.d * root.spacing
            width: 0
            height: root.height

            // Flash: on arriving under the triangle `lit` jumps to 1 (spring),
            // a timeout later it springs back to 0.
            readonly property bool atCentre: tick.index === root.centreIndex
            // Fast spring up (flashIn*), softer one back (flashOut*).
            property real litTarget: 0
            property real lit: tick.litTarget
            Behavior on lit {
                Spring {
                    stiffness: tick.litTarget > 0 ? (root.cfg.flashInStiffness ?? 30) : (root.cfg.flashOutStiffness ?? 5)
                    damp: tick.litTarget > 0 ? (root.cfg.flashInDamping ?? 1) : (root.cfg.flashOutDamping ?? 0.8)
                    eps: 0.005
                }
            }
            onAtCentreChanged: if (tick.atCentre) {
                tick.litTarget = 1;
                unlit.restart();
            }
            Timer {
                id: unlit
                interval: root.cfg.flashHoldMs ?? 260
                onTriggered: tick.litTarget = 0
            }

            Rectangle {
                readonly property real t: Math.max(0, Math.min(1, tick.lit))
                // 0 left of / on the triangle, 1 from half a tick to its right.
                readonly property real past: Math.max(0, Math.min(1, tick.d / 0.5))
                x: -width / 2
                y: root.ticksBottom - height
                width: root.cfg.tickWidth ?? 2
                height: root.tickH
                radius: width / 2
                color: root.mixc(root.mixc(root.tickColor, root.dimColor, past), root.flashColor, t)
                opacity: tick.o
            }
            Text {
                visible: tick.major
                x: -width / 2
                y: 0
                text: tick.index
                color: root.tickColor
                opacity: tick.o * (tick.index === root.centreIndex ? 1 : 0.7)
                font.family: root.theme?.fontFamily ?? "SF Pro Display"
                font.pixelSize: root.labelSize
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
                // A tap on a number jumps there (small control: allowed).
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    onClicked: root.select(tick.index)
                }
            }
        }
    }

    // Pointer: equilateral triangle, apex up, under the centre tick.
    Shape {
        x: root.cx - root.tri / 2
        y: root.triTop
        width: root.tri
        height: root.tri * Math.sqrt(3) / 2
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: root.theme?.timerAccent ?? "#FF9F0A"
            strokeColor: root.theme?.timerAccent ?? "#FF9F0A"
            strokeWidth: 1.5
            joinStyle: ShapePath.RoundJoin
            PathSvg {
                path: `M ${root.tri / 2} 0 L ${root.tri} ${root.tri * Math.sqrt(3) / 2} L 0 ${root.tri * Math.sqrt(3) / 2} Z`
            }
        }
    }

    // Wheel / touchpad (WallCarousel pattern: a button-less MouseArea sees
    // both axes; touchpad = a scroll phase / pixel delta within
    // touchpadHoldMs → horizontal only, else the wheel → vertical only).
    MouseArea {
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.NoButton
        onWheel: wheel => {
            const now = Date.now();
            const phase = wheel.phase ?? Qt.NoScrollPhase;
            if (phase !== Qt.NoScrollPhase || wheel.pixelDelta.x !== 0 || wheel.pixelDelta.y !== 0)
                root.touchpadAt = now;
            if (now - root.touchpadAt < (root.cfg.touchpadHoldMs ?? 150))
                root.wheel(wheel.angleDelta.x * root.touchpadGain(wheel.angleDelta.x), root.cfg.touchpadStep ?? 120);
            else
                root.wheel(wheel.angleDelta.y, 120);
        }
    }
}
