import QtQuick
import QtQuick.Shapes
import "../../components"
import "../../config"

// Animated lightning bolt for the charger events (args.mode). Appearance
// (user): the bolt GROWS BY BEING PAINTED — a fill front sweeps down from
// the top on unplug, up from the bottom on plug-in (`reveal`, a critically
// damped spring; the polygon is clipped by the front's half-plane), with a
// soft light band on the front edge; then a soft neon flicker (two eased
// dips with flares brighter than normal — `lit`, `flash`) and it settles.
//   "break" (unplugged): then cracks along the bolt-shaped centre line
//     into two thin bolts that tilt apart about the bottom (left one left,
//     right one right; `sep`, bouncy). Loop: the halves try to come back
//     together but never reach (near/far), sparks flash in the gap.
//   "join" (plugged in): the halves (tilted apart) are painted bottom-up,
//     flicker, then snap together
//     (`sep` -> 0) and a flash fuses the crack; loop: a charge pulse.
// Halves = the outline split along the crack polyline, each rotated about
// the crack's bottom exit. Fill = the glyph family's vertical gradient.
// Tunables: Config.data.glyphs.bolt.
Item {
    id: g
    property real size: 18
    property color color: "#E58B4D"
    property var args: ({})

    readonly property var cfg: Config.data.glyphs?.bolt ?? ({})
    readonly property bool joining: (g.args?.mode ?? "break") === "join"
    readonly property real handoff: g.cfg.handoff ?? 0.08

    // Bolt outline in unit coords (top-right tip -> bottom-left tip).
    readonly property var unit: [[0.62, 0.0], [0.18, 0.57], [0.47, 0.57], [0.37, 1.0], [0.83, 0.41], [0.54, 0.41]]
    // Crack: itself bolt-shaped (down-left, a jog right, down-left — along
    // the bolt's centre line) from above the top tip to below the bottom
    // one, so the bolt breaks into TWO thin bolts (user). Unit coords; must
    // cross the outline exactly twice and stay inside in between.
    readonly property var crackUnit: g.cfg.crack ?? [[0.62, -0.06], [0.4, 0.47], [0.6, 0.51], [0.36, 1.06]]

    property real reveal: 0
    // Stall guard: plugging the charger makes TLP switch the system to AC
    // (turbo, PCIe ASPM) and the WHOLE compositor freezes for ~0.5 s about
    // 1.5 s later (measured: a 492 ms frame gap mid-flicker; grim frames
    // froze too). Springs then jump to their end and the appearance is
    // simply skipped. If a frame gap longer than `stallMs` hits the
    // appearance (paint / flicker / snap), it replays from the start
    // (at most `stallReplays` times).
    property int replays: 0
    FrameAnimation {
        running: g.begun && (g.joining ? g.phase < 14 : g.phase < 3)
        // currentFrame > 1: the first tick's frameTime is not a real gap.
        onTriggered: if (currentFrame > 1 && frameTime * 1000 > (g.cfg.stallMs ?? 150) && g.replays < (g.cfg.stallReplays ?? 2))
            g.replay()
    }
    function replay(): void {
        g.replays++;
        flicker.stop();
        revealAnim.stop();
        sepAnim.stop();
        flashOff.stop();
        g.lit = 1;
        g.flash = 0;
        g.sep = g.joining ? 1 : 0;
        g.reveal = 0;
        g.phase = 0;
        revealAnim.start();
    }
    property real lit: 1
    property real sep: g.joining ? 1 : 0
    property real flash: 0
    property real pulse: 0
    property bool fused: !g.joining
    property bool cracked: g.joining

    Behavior on pulse { Spring { stiffness: g.cfg.pulseStiffness ?? 6; damp: 0.35; eps: 0.002 } }

    width: g.size
    height: g.size

    // 0 paint, 2 flicker, then break: 3 crack, 4 loop; join: 13 snap, 14 loop.
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
        revealAnim.start();
    }
    // (EventIcon sets `args` before binding `ready`, so the mode / paint
    // direction is known when it begins.)
    Spring { id: revealAnim; target: g; property: "reveal"; to: 1; stiffness: g.cfg.revealStiffness ?? 4; damp: 1; eps: 0.002 }
    onRevealChanged: if (g.phase === 0 && g.reveal >= (g.cfg.flickerAt ?? 0.9)) {
        g.phase = 2;
        flicker.start();
    }
    function afterFlicker(): void {
        if (g.joining) {
            g.phase = 13;
            sepAnim.to = 0;
        } else {
            g.phase = 3;
            g.fused = false;
            g.cracked = true;
            sepAnim.to = 1;
        }
        sepAnim.start();
    }
    onSepChanged: {
        if (g.phase === 3 && g.sep >= 1 - g.handoff) {
            g.phase = 4;
            hover.start();
        } else if (g.phase === 13 && g.sep <= g.handoff) {
            g.phase = 14;
            g.fused = true;
            g.cracked = false;
            g.flash = 1;
            flashOff.start();
            pulseTimer.start();
        }
        if (g.phase === 4 && g.sep < (g.cfg.sparkAt ?? 0.75) && !sparkCooldown.running)
            g.spark();
    }

    // Neon flicker, softened: two eased brightness dips with soft flares
    // (brighter than normal), then it settles.
    SequentialAnimation {
        id: flicker
        ParallelAnimation {
            NumberAnimation { target: g; property: "lit"; to: g.cfg.flickerLow ?? 0.55; duration: g.cfg.flickerMs ?? 110; easing.type: Easing.InOutSine }
        }
        ParallelAnimation {
            NumberAnimation { target: g; property: "lit"; to: 1; duration: (g.cfg.flickerMs ?? 110) * 1.3; easing.type: Easing.InOutSine }
            NumberAnimation { target: g; property: "flash"; to: g.cfg.flareHigh ?? 0.6; duration: (g.cfg.flickerMs ?? 110) * 1.3; easing.type: Easing.OutSine }
        }
        ParallelAnimation {
            NumberAnimation { target: g; property: "lit"; to: g.cfg.flickerMid ?? 0.78; duration: g.cfg.flickerMs ?? 110; easing.type: Easing.InOutSine }
            NumberAnimation { target: g; property: "flash"; to: 0.15; duration: g.cfg.flickerMs ?? 110; easing.type: Easing.InOutSine }
        }
        ParallelAnimation {
            NumberAnimation { target: g; property: "lit"; to: 1; duration: (g.cfg.flickerMs ?? 110) * 1.3; easing.type: Easing.InOutSine }
            NumberAnimation { target: g; property: "flash"; to: g.cfg.flareLow ?? 0.4; duration: (g.cfg.flickerMs ?? 110) * 1.3; easing.type: Easing.OutSine }
        }
        ScriptAction { script: flashOff.restart() }
        PauseAnimation { duration: g.cfg.flickerHoldMs ?? 120 }
        ScriptAction { script: g.afterFlicker() }
    }
    Spring { id: sepAnim; target: g; property: "sep"; stiffness: g.cfg.sepStiffness ?? 5; damp: g.cfg.sepDamping ?? 0.3; eps: 0.003 }
    // Flares are instant; they decay over flashMs.
    NumberAnimation { id: flashOff; target: g; property: "flash"; to: 0; duration: g.cfg.flashMs ?? 420; easing.type: Easing.OutSine }

    // break loop: the halves drift toward each other and back.
    Timer {
        id: hover
        property bool near: false
        interval: g.cfg.hoverMs ?? 650
        repeat: true
        onTriggered: {
            hover.near = !hover.near;
            sepAnim.stop();
            sepAnim.to = hover.near ? (g.cfg.nearSep ?? 0.45) : 1;
            sepAnim.start();
        }
    }
    // join loop: a soft charge pulse.
    Timer {
        id: pulseTimer
        interval: g.cfg.pulseMs ?? 1300
        repeat: true
        onTriggered: {
            g.pulse = 1;
            pulseBack.start();
        }
    }
    Timer { id: pulseBack; interval: 140; onTriggered: g.pulse = 0 }

    // ---- geometry -------------------------------------------------------
    readonly property var poly: g.unit.map(p => [p[0] * g.size, p[1] * g.size])
    readonly property var crack: g.crackUnit.map(p => [p[0] * g.size, p[1] * g.size])
    // Splits the outline along the crack polyline: the first and last
    // crossings (entry E near the top, exit X near the bottom), then each
    // half = outline walk between them + the inner crack points.
    readonly property var halves: {
        const P = g.poly, C = g.crack, hits = [];
        for (let k = 0; k + 1 < C.length; k++) {
            const a = C[k], b = C[k + 1];
            for (let i = 0; i < P.length; i++) {
                const c = P[i], d = P[(i + 1) % P.length];
                const den = (b[0] - a[0]) * (d[1] - c[1]) - (b[1] - a[1]) * (d[0] - c[0]);
                if (Math.abs(den) < 1e-9)
                    continue;
                const t = ((c[0] - a[0]) * (d[1] - c[1]) - (c[1] - a[1]) * (d[0] - c[0])) / den;
                const u = ((c[0] - a[0]) * (b[1] - a[1]) - (c[1] - a[1]) * (b[0] - a[0])) / den;
                if (t >= 0 && t <= 1 && u >= 0 && u <= 1)
                    hits.push({ s: k + t, edge: i, pt: [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t] });
            }
        }
        if (hits.length < 2)
            return null;
        hits.sort((m, n) => m.s - n.s);
        const E = hits[0], X = hits[hits.length - 1];
        const inner = C.filter((p, k) => k > E.s && k < X.s);
        const walk = (from, to) => {
            const out = [];
            for (let i = (from + 1) % P.length; ; i = (i + 1) % P.length) {
                out.push(P[i]);
                if (i === to)
                    break;
            }
            return out;
        };
        const a = [E.pt, ...walk(E.edge, X.edge), X.pt, ...inner.slice().reverse()];
        const b = [X.pt, ...walk(X.edge, E.edge), E.pt, ...inner];
        const cx = pts => pts.reduce((sum, p) => sum + p[0], 0) / pts.length;
        const res = { pivot: X.pt, entry: E.pt, inner: inner };
        res.left = cx(a) < cx(b) ? a : b;
        res.right = cx(a) < cx(b) ? b : a;
        return res;
    }
    // Rotate about the pivot (the crack's exit at the bottom): + = clockwise.
    function turned(pts: var, deg: real, dx: real): var {
        const o = g.halves.pivot, r = deg * Math.PI / 180, c = Math.cos(r), sn = Math.sin(r);
        return pts.map(p => [o[0] + (p[0] - o[0]) * c - (p[1] - o[1]) * sn + dx, o[1] + (p[0] - o[0]) * sn + (p[1] - o[1]) * c]);
    }
    function svg(pts: var, dx: real, dy: real): string {
        if (pts.length === 0)
            return "";
        let p = `M ${pts[0][0] + dx} ${pts[0][1] + dy}`;
        for (let i = 1; i < pts.length; i++)
            p += ` L ${pts[i][0] + dx} ${pts[i][1] + dy}`;
        return p + " Z";
    }
    // Each half tilts away about the bottom pivot (left one to the left,
    // right one to the right) by `sep` × tiltDeg, plus a hairline gap.
    readonly property real tilt: Math.max(0, g.sep) * (g.cfg.tiltDeg ?? 16)
    readonly property real gapPx: g.cracked ? g.size * (g.cfg.crackGap ?? 0.025) : 0
    readonly property var shapes: (g.fused || !g.halves) ? [g.poly]
        : [g.turned(g.halves.left, -g.tilt, -g.gapPx / 2), g.turned(g.halves.right, g.tilt, g.gapPx / 2)]
    // Paint front (y, px): sweeps the shapes' vertical extent, down from the
    // top on unplug, up from the bottom on plug-in.
    readonly property var extent: {
        let lo = 1e9, hi = -1e9;
        for (const sh of g.shapes)
            for (const p of sh) {
                lo = Math.min(lo, p[1]);
                hi = Math.max(hi, p[1]);
            }
        return [lo, hi];
    }
    readonly property real r: Math.max(0, Math.min(1, g.reveal))
    readonly property real front: g.joining ? g.extent[1] - (g.extent[1] - g.extent[0]) * g.r
        : g.extent[0] + (g.extent[1] - g.extent[0]) * g.r
    // Sutherland–Hodgman against the front's half-plane (fine for the
    // concave bolt: one convex clip edge).
    function painted(pts: var): var {
        if (g.r >= 1)
            return pts;
        const keep = p => g.joining ? p[1] >= g.front : p[1] <= g.front;
        const out = [];
        for (let i = 0; i < pts.length; i++) {
            const p = pts[i], q = pts[(i + 1) % pts.length];
            if (keep(p))
                out.push(p);
            if (keep(p) !== keep(q)) {
                const t = (g.front - p[1]) / (q[1] - p[1]);
                out.push([p[0] + (q[0] - p[0]) * t, g.front]);
            }
        }
        return out.length >= 3 ? out : [];
    }
    readonly property string fillPath: g.shapes.map(sh => g.svg(g.painted(sh), 0, 0)).join(" ")

    // ---- sparks (break loop) -------------------------------------------
    // Sparks where the gap opens widest: the upper part of the crack.
    readonly property real gapX: g.size * (g.cfg.sparkX ?? 0.5)
    readonly property real gapY: g.size * (g.cfg.sparkY ?? 0.3)
    function spark(): void {
        sparkCooldown.restart();
        for (let i = 0; i < sparks.count; i++) {
            const s = sparks.itemAt(i);
            s.rotation = Math.random() * 180;
            s.dx = (Math.random() - 0.5) * g.size * 0.3;
            s.dy = (Math.random() - 0.5) * g.size * 0.12;
            s.flashIt();
        }
    }
    Timer { id: sparkCooldown; interval: g.cfg.sparkCooldownMs ?? 500 }

    Item {
        anchors.fill: parent
        scale: 1 + (g.cfg.pulseScale ?? 0.07) * g.pulse
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            opacity: g.lit
            ShapePath {
                strokeWidth: -1
                strokeColor: "transparent"
                fillGradient: LinearGradient {
                    x1: 0; y1: 0
                    x2: 0; y2: g.size
                    GradientStop { position: 0; color: Qt.lighter(g.color, (g.cfg.lighter ?? 1.2) + 0.5 * g.flash) }
                    GradientStop { position: 1; color: Qt.darker(g.color, g.cfg.darker ?? 1.4) }
                }
                PathSvg { path: g.fillPath }
            }
        }
        // Soft light band riding the paint front (fades out as it lands).
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            opacity: Math.max(0, 1 - Math.pow(g.r, 6)) * g.lit
            ShapePath {
                strokeWidth: -1
                strokeColor: "transparent"
                fillGradient: LinearGradient {
                    readonly property real band: g.size * (g.cfg.frontBand ?? 0.22)
                    x1: 0; y1: g.joining ? g.front + band : g.front - band
                    x2: 0; y2: g.front
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: Qt.alpha(Qt.lighter(g.color, g.cfg.frontLighter ?? 1.8), g.cfg.frontAlpha ?? 0.9) }
                }
                PathSvg { path: g.fillPath }
            }
        }

        Repeater {
            id: sparks
            model: g.cfg.sparks ?? 3
            delegate: Rectangle {
                id: spk
                property real dx: 0
                property real dy: 0
                width: g.size * 0.2
                height: Math.max(1, g.size * 0.06)
                radius: height / 2
                color: g.cfg.sparkColor ?? "#FFF4C2"
                x: g.gapX + dx - width / 2
                y: g.gapY + dy - height / 2
                opacity: 0
                function flashIt(): void {
                    spkAnim.restart();
                }
                SequentialAnimation {
                    id: spkAnim
                    PauseAnimation { duration: Math.random() * 80 }
                    NumberAnimation { target: spk; property: "opacity"; to: 1; duration: 40 }
                    NumberAnimation { target: spk; property: "opacity"; to: 0; duration: g.cfg.sparkMs ?? 160; easing.type: Easing.OutQuad }
                }
            }
        }
    }
}
