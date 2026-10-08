import QtQuick
import QtQuick.Shapes
import "../components"
import "../config"

// Animated pacman glyph for the "pacman updates" event (drawn, not a font
// glyph). Reveal: a line grows from the centre to the right (`grow`), then
// sweeps 330° clockwise filling the disc (`sweep`) while its starting edge
// drops 30° — the lower jaw opening. Then it chomps in a loop: a dot
// scales + fades in to the right (SkipBtn's staged-triangle entry), FLIES
// left at a constant speed (`fly`, timed linear — user: not a spring) into
// the body's live centre; past `biteAt` of the flight the jaws close behind
// it (`bite`) and the eye (black disc, upper half) squeezes shut, pacman
// recoils a bit to the left on an under-damped spring, the dot is swallowed
// (drawn under the body), the jaws reopen, the eye opens and pacman springs
// back; bites come in pairs (`series`), then a `restMs` break. Everything else runs on springs. Phases chain when the driver gets within
// `handoff` of its target, NOT onFinished: an over-damped SpringAnimation
// creeps the last few % for ~1 s (the line just sat there).
// Tunables: Config.data.glyphs.pacman (sizes are fractions of `size`).
Item {
    id: g
    property real size: 18
    property color color: "#D8BE52"
    property color eyeColor: "#000000"

    readonly property var cfg: Config.data.glyphs?.pacman ?? ({})
    readonly property real stroke: g.size * (g.cfg.stroke ?? 0.1)
    readonly property real r: g.size / 2 - g.stroke / 2
    readonly property real mouthHalf: g.cfg.mouth ?? 30

    // Phase drivers (0..1).
    property real grow: 0
    property real sweep: 0
    property real dotIn: 0
    property real bite: 0
    property real fly: 0
    // Recoil follows the jaw's TARGET on its own bouncy spring.
    property bool closing: false
    property real recoil: g.closing ? 1 : 0
    Behavior on recoil { Spring { stiffness: g.cfg.recoilStiffness ?? 10; damp: g.cfg.recoilDamping ?? 0.25; eps: 0.002 } }

    // Jaw half-angle and the filled sector [s, e] (degrees, clockwise from 3 o'clock).
    readonly property real m: Math.max(0, g.mouthHalf * (1 - g.bite))
    readonly property real s: g.sweep * g.m
    readonly property real e: g.sweep * (360 - g.m)

    width: g.size
    height: g.size

    Component.onCompleted: growAnim.start()

    readonly property real handoff: g.cfg.handoff ?? 0.08
    // 0 grow, 1 sweep, 2 idle (pause / dot), 3 bite, 4 reopen.
    property int phase: 0
    property int eaten: 0
    onGrowChanged: if (g.phase === 0 && g.grow >= 1 - g.handoff) {
        g.phase = 1;
        sweepAnim.start();
    }
    onSweepChanged: if (g.phase === 1 && g.sweep >= 1 - g.handoff) {
        g.phase = 2;
        pause.start();
    }
    // The flight starts as the dot first reaches full size (its overshoot
    // settles while it already flies).
    onDotInChanged: if (g.phase === 2 && dotAnim.running && g.dotIn >= 1 - g.handoff) {
        g.phase = 3;
        flyAnim.start();
    }
    // Jaws close behind the dot once it is `biteAt` of the way in.
    onFlyChanged: {
        if (g.phase === 3 && !g.closing && g.fly >= (g.cfg.biteAt ?? 0.5)) {
            g.closing = true;
            biteAnim.stop();
            biteAnim.to = 1;
            biteAnim.start();
        }
        g.swallow();
    }
    onBiteChanged: {
        g.swallow();
        // Series of `series` bites with `pauseMs` between them, then a
        // longer `restMs` break. Inside a series the next dot already
        // spawns while the jaws are still reopening (`seriesReopen`).
        const inSeries = (g.eaten + 1) % Math.max(1, g.cfg.series ?? 2) !== 0;
        const reopened = inSeries ? (g.cfg.seriesReopen ?? 0.5) : g.handoff;
        if (g.phase === 4 && g.bite <= reopened) {
            g.phase = 2;
            g.eaten++;
            pause.interval = inSeries ? (g.cfg.pauseMs ?? 0) : (g.cfg.restMs ?? 450);
            pause.start();
        }
    }
    // Swallowed (dot arrived AND jaws shut): the dot sits under the closed
    // body, so it can vanish; then the jaws reopen.
    function swallow(): void {
        if (g.phase !== 3 || g.fly < 1 || g.bite < 1 - g.handoff)
            return;
        g.phase = 4;
        g.dotIn = 0;
        g.fly = 0;
        g.closing = false;
        biteAnim.stop();
        biteAnim.to = 0;
        biteAnim.start();
    }

    Spring {
        id: growAnim
        target: g
        property: "grow"
        to: 1
        stiffness: g.cfg.revealStiffness ?? 7
        damp: 1
        eps: 0.003
    }
    Spring {
        id: sweepAnim
        target: g
        property: "sweep"
        to: 1
        stiffness: g.cfg.revealStiffness ?? 7
        damp: 1
        eps: 0.002
    }
    Timer {
        id: pause
        interval: g.cfg.pauseMs ?? 0
        onTriggered: dotAnim.start()
    }
    Spring {
        id: dotAnim
        target: g
        property: "dotIn"
        from: 0
        to: 1
        stiffness: g.cfg.dotStiffness ?? 12
        damp: 0.5
        eps: 0.003

    }
    NumberAnimation {
        id: flyAnim
        target: g
        property: "fly"
        from: 0
        to: 1
        duration: g.cfg.flyMs ?? 260
        easing.type: Easing.Linear
    }
    Spring {
        id: biteAnim
        target: g
        property: "bite"
        stiffness: g.cfg.biteStiffness ?? 12
        damp: 1
        eps: 0.003
    }

    // The dot: right of the centre, flies into the body centre.
    Rectangle {
        readonly property real d: g.size * (g.cfg.dot ?? 0.24)
        readonly property real startX: g.size / 2 + g.r * (g.cfg.dotStart ?? 1.5)
        width: d
        height: d
        radius: d / 2
        color: g.color
        // Aims at the body's LIVE centre (it recoils while the dot flies).
        x: startX + (g.size / 2 + body.x - startX) * g.fly - d / 2
        y: (g.size - d) / 2
        scale: Math.max(0, g.dotIn)
        opacity: Math.max(0, Math.min(1, g.dotIn))
    }

    Item {
        id: body
        width: g.size
        height: g.size
        x: -g.size * (g.cfg.recoil ?? 0.18) * g.recoil

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: g.color
                strokeColor: g.color
                strokeWidth: g.stroke
                joinStyle: ShapePath.RoundJoin
                capStyle: ShapePath.RoundCap
                PathMove {
                    x: g.size / 2
                    y: g.size / 2
                }
                PathLine {
                    x: g.size / 2 + g.r * g.grow * Math.cos(g.s * Math.PI / 180)
                    y: g.size / 2 + g.r * g.grow * Math.sin(g.s * Math.PI / 180)
                }
                PathAngleArc {
                    centerX: g.size / 2
                    centerY: g.size / 2
                    radiusX: g.r * g.grow
                    radiusY: g.r * g.grow
                    startAngle: g.s
                    sweepAngle: g.e - g.s
                    moveToStart: false
                }
                PathLine {
                    x: g.size / 2
                    y: g.size / 2
                }
            }
        }

        // Eye: squeezes shut while the jaws close (height follows `bite`),
        // appears with the end of the reveal sweep.
        Rectangle {
            readonly property real d: g.size * (g.cfg.eye ?? 0.17)
            readonly property real cx: g.size / 2 + g.r * (g.cfg.eyeX ?? 0.12)
            readonly property real cy: g.size / 2 - g.r * (g.cfg.eyeY ?? 0.5)
            width: d
            height: Math.max(d * 0.18, d * (1 - (g.cfg.eyeClose ?? 0.85) * Math.max(0, Math.min(1, g.bite))))
            radius: Math.min(width, height) / 2
            x: cx - width / 2
            y: cy - height / 2
            color: g.eyeColor
            opacity: Math.max(0, Math.min(1, (g.sweep - 0.7) / 0.3))
        }
    }
}
