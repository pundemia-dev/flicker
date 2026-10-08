import QtQuick
import QtQuick.Shapes
import "../../components"
import "../../config"

// Animated coffee cup for the caffeine event. A stroked cup (open top,
// rounded bottom) with a handle on the left (`handleSide`); inside, separated from the
// wall by a gap, the coffee — a filled body whose surface is a small
// travelling sine (the ghost hem idea, smaller amplitude).
// Reveal: the walls rise from the bottom curve (`draw`), the handle sweeps
// out (`handle`), then the coffee pours in to its level (`level`); with
// `args.drain` (caffeine off) the cup appears full and the coffee drains.
// Look: the pacman / ghost gradient fill on the coffee, the cup a stroke in
// a lighter coffee colour (Shape has no stroke gradients). Tunables: Config.data.glyphs.coffee.
Item {
    id: g
    property real size: 18
    property color color: "#C8915A"
    property var args: ({})

    readonly property var cfg: Config.data.glyphs?.coffee ?? ({})
    readonly property bool drain: g.args?.drain ?? false
    readonly property real handoff: g.cfg.handoff ?? 0.08

    // Geometry (fractions of the size from config).
    readonly property real st: g.size * (g.cfg.stroke ?? 0.1)
    readonly property real cw: g.size * (g.cfg.cupWidth ?? 0.8)
    readonly property real ch: g.size * (g.cfg.cupHeight ?? 0.56)
    readonly property real hr: g.size * (g.cfg.handleRadius ?? 0.13)
    // Handle side: -1 left (default, user), 1 right.
    readonly property int side: (g.cfg.handleSide ?? "left") === "right" ? 1 : -1
    readonly property real x0: (g.size - g.cw - g.hr) / 2 + (g.side < 0 ? g.hr : 0)
    readonly property real x1: g.x0 + g.cw
    readonly property real y0: (g.size - g.ch) / 2 + g.size * (g.cfg.cupDrop ?? 0.06)
    readonly property real y1: g.y0 + g.ch
    readonly property real rb: Math.min(g.cw / 2, g.size * (g.cfg.bottomRadius ?? 0.3))
    readonly property real gap: g.size * (g.cfg.gap ?? 0.07)
    // Cup in the coffee colour too (user), a touch lighter than the coffee
    // so the gap still separates them.
    readonly property color cupTop: Qt.lighter(g.color, g.cfg.cupLighter ?? 1.2)

    property real draw: 0
    property real handle: 0
    property real level: g.drain ? 1 : 0
    property real wave: 0

    width: g.size
    height: g.size

    // 0 draw, 1 handle, 2 pour / drain, 3 idle.
    property int phase: 0
    // Starts once the host says the icon is visible enough (`ready`, bound
    // by EventIcon to its fade-in): started at creation, the reveal ran
    // under the blur-fade-in and was sometimes invisible (user).
    property bool ready: false
    property bool begun: false
    onReadyChanged: g.tryBegin()
    Component.onCompleted: g.tryBegin()
    function tryBegin(): void {
        if (!g.ready || g.begun)
            return;
        g.begun = true;
        drawAnim.start();
    }
    onDrawChanged: if (g.phase === 0 && g.draw >= 1 - g.handoff) {
        g.phase = 1;
        handleAnim.start();
    }
    onHandleChanged: if (g.phase === 1 && g.handle >= 1 - g.handoff) {
        g.phase = 2;
        levelAnim.to = g.drain ? 0 : 1;
        levelAnim.start();
    }

    Spring { id: drawAnim; target: g; property: "draw"; to: 1; stiffness: g.cfg.revealStiffness ?? 7; damp: 1; eps: 0.003 }
    Spring { id: handleAnim; target: g; property: "handle"; to: 1; stiffness: g.cfg.revealStiffness ?? 7; damp: 1; eps: 0.003 }
    // Pour: under-damped, the surface overshoots and settles (slosh).
    Spring { id: levelAnim; target: g; property: "level"; stiffness: g.cfg.pourStiffness ?? 3; damp: g.cfg.pourDamping ?? 0.3; eps: 0.002 }

    NumberAnimation on wave {
        from: 0
        to: 2 * Math.PI
        duration: g.cfg.waveMs ?? 1100
        loops: Animation.Infinite
    }

    // Cup outline (stroked): walls rise from the bottom curve with `draw`.
    function cupPath(): string {
        const top = g.y1 - g.rb - (g.y1 - g.rb - g.y0) * Math.max(0, Math.min(1, g.draw));
        return `M ${g.x0} ${top} L ${g.x0} ${g.y1 - g.rb} Q ${g.x0} ${g.y1} ${g.x0 + g.rb} ${g.y1}`
            + ` L ${g.x1 - g.rb} ${g.y1} Q ${g.x1} ${g.y1} ${g.x1} ${g.y1 - g.rb} L ${g.x1} ${top}`;
    }
    // Coffee: inside the walls by half the stroke + gap, surface = small
    // travelling sine at `level` of the inner height.
    readonly property real ixl: g.x0 + g.st / 2 + g.gap
    readonly property real ixr: g.x1 - g.st / 2 - g.gap
    readonly property real iyb: g.y1 - g.st / 2 - g.gap
    readonly property real iyt: g.y0 + g.size * (g.cfg.headroom ?? 0.1)
    readonly property real irb: Math.max(0, g.rb - g.st / 2 - g.gap)
    function liquidPath(): string {
        const lv = Math.max(0, Math.min(1.08, g.level));
        if (lv < 0.01)
            return "";
        const surf = g.iyb - (g.iyb - g.iyt) * lv;
        const w = g.ixr - g.ixl;
        const amp = g.size * (g.cfg.waveAmp ?? 0.035) * Math.min(1, lv * 3);
        const k = Math.PI * (g.cfg.waveHalves ?? 2) / w;
        const n = Math.max(4, g.cfg.waveSegments ?? 12);
        const y = x => Math.min(g.iyb - 0.3, surf - amp * Math.sin(k * (x - g.ixl) + g.wave));
        const r = Math.min(g.irb, Math.max(0, g.iyb - surf));
        let p = `M ${g.ixl} ${y(g.ixl)}`;
        for (let i = 1; i <= n; i++) {
            const x = g.ixl + w * i / n;
            p += ` L ${x} ${y(x)}`;
        }
        p += ` L ${g.ixr} ${g.iyb - r} Q ${g.ixr} ${g.iyb} ${g.ixr - r} ${g.iyb}`;
        p += ` L ${g.ixl + r} ${g.iyb} Q ${g.ixl} ${g.iyb} ${g.ixl} ${g.iyb - r} Z`;
        return p;
    }

    // Coffee (under the cup outline); fades in with the walls (a draining
    // cup starts full).
    Shape {
        anchors.fill: parent
        opacity: Math.min(1, g.draw * 1.5)
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillGradient: LinearGradient {
                x1: 0; y1: g.iyt
                x2: 0; y2: g.iyb
                GradientStop { position: 0; color: Qt.lighter(g.color, g.cfg.lighter ?? 1.18) }
                GradientStop { position: 1; color: Qt.darker(g.color, g.cfg.darker ?? 1.45) }
            }
            PathSvg { path: g.liquidPath() }
        }
    }

    // Cup + handle (stroked).
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: "transparent"
            strokeWidth: g.st
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            strokeColor: g.cupTop
            PathSvg { path: g.cupPath() }
        }
        ShapePath {
            fillColor: "transparent"
            strokeWidth: g.st
            capStyle: ShapePath.RoundCap
            strokeColor: Qt.alpha(g.cupTop, Math.min(1, g.handle * 3))
            PathAngleArc {
                centerX: g.side < 0 ? g.x0 : g.x1
                centerY: g.y0 + g.ch * (g.cfg.handleY ?? 0.42)
                radiusX: g.hr
                radiusY: g.hr * (g.cfg.handleSquash ?? 1.15)
                startAngle: (g.side < 0 ? 180 : 0) - 80 * Math.max(0.01, g.handle)
                sweepAngle: 160 * Math.max(0.01, g.handle)
            }
        }
    }
}
