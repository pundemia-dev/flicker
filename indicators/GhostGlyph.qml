import QtQuick
import QtQuick.Shapes
import "../components"
import "../config"

// Animated Pac-Man ghost for the "AUR updates" event (follows the pacman
// event). Reveal: the head arc draws out from the top centre to both sides
// (`head`, a stroked line like pacman's), then the sides drop and the skirt
// opens into a wavy hem (`drop`), then the eyes pop in (`eyesIn`). Loop: the hem
// ripple (`wave`, a continuous timed cycle — a looping wave has no spring
// target; same exception as the battery wipers), the eyes — HOLES in the
// body, the island shows through (user) — look left / right (`look` on a
// spring) and on every other look-around the whole ghost moves toward the
// look with a delay (a sideways step, not a tilt — user), leaning into it
// (shear: rectangle -> parallelogram, hem planted): first round
// steps left (on its left look), the next steps right (on its right look). Fill = the pacman look: vertical
// gradient + a light rim along the head (WallCardRim style). Phases hand
// over at `handoff` of the target (see PacmanGlyph). Tunables:
// Config.data.glyphs.ghost (sizes are fractions of `size`).
Item {
    id: g
    property real size: 18
    property color color: "#5AA9FF"
    property color rimTop: "#8CFFFFFF"
    property color rimBottom: "#40FFFFFF"

    readonly property var cfg: Config.data.glyphs?.ghost ?? ({})
    readonly property color fillTop: Qt.lighter(g.color, g.cfg.lighter ?? 1.18)
    readonly property color fillBottom: Qt.darker(g.color, g.cfg.darker ?? 1.45)
    readonly property real stroke: g.size * (g.cfg.stroke ?? 0.1)
    readonly property real rimW: g.size * (g.cfg.rim ?? 0.06)
    // Body box: W wide, H tall, head radius R (half the width).
    readonly property real bw: g.size * (g.cfg.width ?? 0.86)
    readonly property real bh: g.size
    readonly property real rr: g.bw / 2
    readonly property real handoff: g.cfg.handoff ?? 0.08

    property real head: 0
    property real drop: 0
    property real eyesIn: 0
    property real wave: 0
    property real look: 0
    property real sway: 0
    // Nervous glances + a reluctant lean (user): both start fast and
    // settle slowly — timed decelerating curves, not springs (user pick).
    // Eyes dart (lookMs, OutExpo). The step lunges (swayMs, OutExpo: most of
    // the way in the first frames) and drifts back slower (swayBackMs,
    // OutCubic). Curve + duration are set imperatively right before the
    // value changes (stepTo), so the Behavior starts with the right one.
    // The step must be several px: over ~2.5 px the lunge fit in 2-3
    // frames and read as an even crawl (user: "not on a curve at all").
    Behavior on look { NumberAnimation { duration: g.cfg.lookMs ?? 140; easing.type: Easing.OutExpo } }
    Behavior on sway { NumberAnimation { id: swayAnim } }
    function stepTo(v: real): void {
        const out = v !== 0;
        swayAnim.duration = out ? (g.cfg.swayMs ?? 260) : (g.cfg.swayBackMs ?? 520);
        swayAnim.easing.type = out ? Easing.OutExpo : Easing.OutCubic;
        // Lean into the motion: the body shears (rectangle -> parallelogram,
        // hem planted, head leading) while it moves, then straightens on a
        // bouncy spring. Returning leans the other way.
        const dir = out ? v : -g.sway;
        // Builds up gently (leanIn* spring), straightens bouncily (leanOut*).
        leanSpring.spring = g.cfg.leanInStiffness ?? 2.5;
        leanSpring.damping = g.cfg.leanInDamping ?? 0.6;
        g.lean = Math.sign(dir) * (out ? 1 : (g.cfg.leanBack ?? 0.6));
        leanReset.interval = out ? (g.cfg.leanHoldMs ?? 280) : (g.cfg.leanBackHoldMs ?? 320);
        leanReset.restart();
        g.sway = v;
    }
    property real lean: 0
    Behavior on lean { Spring { id: leanSpring; eps: 0.002 } }
    Timer {
        id: leanReset
        onTriggered: {
            leanSpring.spring = g.cfg.leanOutStiffness ?? 7;
            leanSpring.damping = g.cfg.leanOutDamping ?? 0.3;
            g.lean = 0;
        }
    }

    width: g.size
    height: g.size

    // 0 head, 1 drop, 2 eyes, 3 loop.
    property int phase: 0
    Component.onCompleted: headAnim.start()
    onHeadChanged: if (g.phase === 0 && g.head >= 1 - g.handoff) {
        g.phase = 1;
        dropAnim.start();
    }
    onDropChanged: if (g.phase === 1 && g.drop >= 1 - g.handoff) {
        g.phase = 2;
        eyesAnim.start();
    }
    onEyesInChanged: if (g.phase === 2 && g.eyesIn >= 1 - g.handoff) {
        g.phase = 3;
        lookTimer.start();
    }

    Spring { id: headAnim; target: g; property: "head"; to: 1; stiffness: g.cfg.revealStiffness ?? 7; damp: 1; eps: 0.003 }
    Spring { id: dropAnim; target: g; property: "drop"; to: 1; stiffness: g.cfg.revealStiffness ?? 7; damp: 1; eps: 0.003 }
    Spring { id: eyesAnim; target: g; property: "eyesIn"; to: 1; stiffness: g.cfg.eyesStiffness ?? 10; damp: 0.45; eps: 0.003 }

    NumberAnimation on wave {
        running: g.drop > 0
        from: 0
        to: 2 * Math.PI
        duration: g.cfg.waveMs ?? 700
        loops: Animation.Infinite
    }

    // Look-around: L, R, L, R, ... Sways on looks 0 (left) and 3 (right)
    // of every 4 = every other look-around, alternating sides.
    property int looks: 0
    Timer {
        id: lookTimer
        interval: g.cfg.lookHoldMaxMs ?? 800
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            // Uneven holds read nervous: each glance lasts a random time
            // between lookHoldMinMs and lookHoldMaxMs.
            const lo = g.cfg.lookHoldMinMs ?? 450, hi = g.cfg.lookHoldMaxMs ?? 800;
            lookTimer.interval = lo + Math.random() * Math.max(0, hi - lo);
            const dir = g.looks % 2 === 0 ? -1 : 1;
            g.look = dir;
            const k = g.looks % 4;
            if (k === 0 || k === 3) {
                swayIn.dir = dir;
                swayIn.restart();
            }
            g.looks++;
        }
    }
    Timer {
        id: swayIn
        property int dir: -1
        interval: g.cfg.swayDelayMs ?? 180
        onTriggered: {
            g.stepTo(swayIn.dir);
            swayOut.restart();
        }
    }
    Timer {
        id: swayOut
        interval: g.cfg.swayHoldMs ?? 380
        onTriggered: g.stepTo(0)
    }

    // Outline as SVG: the head arc only while it draws, then head + sides +
    // the travelling hem wave.
    function outline(): string {
        const W = g.bw, R = g.rr, H = g.bh;
        const pt = deg => [R + R * Math.cos(deg * Math.PI / 180), R + R * Math.sin(deg * Math.PI / 180)];
        if (g.phase === 0 || g.drop <= 0.001) {
            const span = 90 * Math.max(0.001, Math.min(1, g.head));
            const a = pt(-90 - span), b = pt(-90 + span);
            return `M ${a[0]} ${a[1]} A ${R} ${R} 0 0 1 ${b[0]} ${b[1]}`;
        }
        const d = Math.max(0, Math.min(1, g.drop));
        const yb = R + (H - R) * d;
        // Hem: `feetWaves` half-waves of a small sine across the width,
        // travelling with `wave`; sampled finely enough to read smooth.
        const amp = g.size * (g.cfg.feet ?? 0.07) * d;
        const k = Math.PI * (g.cfg.feetWaves ?? 2) / W;
        const n = Math.max(4, g.cfg.feetSegments ?? 16);
        const hem = x => yb - amp * (0.5 + 0.5 * Math.sin(k * x + g.wave));
        // Small rounding where the hem meets the sides (`hemRound`): the
        // side stops short and a quadratic turns into the hem.
        const c = Math.min(W / 4, g.size * (g.cfg.hemRound ?? 0.1)) * d;
        let p = `M 0 ${R} A ${R} ${R} 0 0 1 ${W} ${R} L ${W} ${hem(W) - c}`;
        p += ` Q ${W} ${hem(W)} ${W - c} ${hem(W - c)}`;
        for (let i = 1; i < n; i++) {
            const x = W - c - (W - 2 * c) * i / n;
            p += ` L ${x} ${hem(x)}`;
        }
        p += ` L ${c} ${hem(c)} Q 0 ${hem(0)} 0 ${hem(0) - c} Z`;
        // Eyes = holes in the body (even-odd fill): the island shows
        // through. They pop in with `eyesIn` and shift toward `look`.
        const e = Math.max(0, g.eyesIn);
        if (e > 0.001) {
            const rx = W * (g.cfg.eyeWidth ?? 0.17) / 2 * e;
            const ry = W * (g.cfg.eyeHeight ?? 0.22) / 2 * e;
            const cy = R * (g.cfg.eyeY ?? 0.95);
            for (const side of [-1, 1]) {
                const cx = W / 2 + side * W * (g.cfg.eyeSpread ?? 0.19) + g.look * W * (g.cfg.lookShift ?? 0.07);
                p += ` M ${cx - rx} ${cy} A ${rx} ${ry} 0 1 0 ${cx + rx} ${cy} A ${rx} ${ry} 0 1 0 ${cx - rx} ${cy} Z`;
            }
        }
        return p;
    }
    // Top rim: a sliver along the head arc (180° -> 360°).
    function rimPath(): string {
        const R = g.rr, ri = Math.max(0, R - g.rimW), W = g.bw;
        return `M 0 ${R} A ${R} ${R} 0 0 1 ${W} ${R} L ${W - g.rimW} ${R} A ${ri} ${ri} 0 0 0 ${g.rimW} ${R} Z`;
    }

    Item {
        id: body
        width: g.bw
        height: g.bh
        x: (g.size - g.bw) / 2 + g.size * (g.cfg.swayShift ?? 0.24) * g.sway
        // Shear about the bottom edge: x' = x + k * (y - H), so the hem
        // stays put and the head shifts by `lean` × leanShift of the size.
        readonly property real k: -g.lean * g.size * (g.cfg.leanShift ?? 0.18) / g.bh
        transform: Matrix4x4 {
            matrix: Qt.matrix4x4(1, body.k, 0, -body.k * g.bh,
                                 0, 1, 0, 0,
                                 0, 0, 1, 0,
                                 0, 0, 0, 1)
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillRule: ShapePath.OddEvenFill
                fillGradient: LinearGradient {
                    x1: 0; y1: 0
                    x2: 0; y2: g.bh
                    GradientStop { position: 0; color: g.fillTop }
                    GradientStop { position: 1; color: g.fillBottom }
                }
                strokeColor: Qt.alpha(g.color, Math.max(0, 1 - g.drop))
                strokeWidth: g.stroke
                joinStyle: ShapePath.RoundJoin
                capStyle: ShapePath.RoundCap
                PathSvg { path: g.outline() }
            }
        }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            opacity: Math.max(0, Math.min(1, (g.drop - 0.7) / 0.3))
            ShapePath {
                strokeWidth: -1
                strokeColor: "transparent"
                fillGradient: LinearGradient {
                    x1: 0; y1: 0
                    x2: 0; y2: g.rr
                    GradientStop { position: 0; color: g.rimTop }
                    GradientStop { position: 0.45; color: Qt.alpha(g.rimTop, g.rimTop.a * 0.55) }
                    GradientStop { position: 1; color: "transparent" }
                }
                PathSvg { path: g.rimPath() }
            }
        }
    }
}
