import QtQuick
import "../components"

// Side arcs: WiFi signal (left, yellow) and battery (right, coloured by
// level). Each arc is a circle concentric with the bar end's rounding
// centre, drawn behind the island so only the outer crescent shows.
// The coloured fill grows from the bottom upwards; the remainder from the
// fill end up to the top is a grey track (DashProgress pattern). A soft
// black halo (layered translucent strokes, no hard outline) sits behind
// the arcs, so the thin strokes stay readable over bright windows. Arcs are
// only shown in the bar (Island) state, fading away in other states.
Item {
    id: root
    required property var network
    required property var battery
    required property var theme
    required property var cfg
    required property var batteryCfg
    required property real islandRadius
    required property bool visibleInState

    readonly property color batteryColor: battery.percent > root.batteryCfg.warnPercent
        ? theme.batteryGood
        : (battery.percent > root.batteryCfg.lowPercent ? theme.batteryWarn : theme.batteryLow)

    // Low battery "wipers" (tempShell RadialSliderIcon connecting pattern):
    // below battery.lowPercent and not charging the fill sweeps from the
    // real level up to full and back, forever, so the arc is not missed.
    // Timed easing like the reference (a looping sweep, not a spring —
    // same user exception as hideProgress); alwaysRunToEnd parks it at 0.
    property real wipe: 0
    SequentialAnimation on wipe {
        running: root.battery.low && root.visible
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation { from: 0; to: 1; duration: root.cfg.wiperMs ?? 900; easing.type: Easing.InOutCubic }
        NumberAnimation { from: 1; to: 0; duration: root.cfg.wiperMs ?? 900; easing.type: Easing.InOutCubic }
    }

    // Rounding centre of the bar ends (capsule clamp): the arc circles
    // share it, so arcs wrap the island ends concentrically.
    readonly property real endCenter: Math.min(root.islandRadius, root.height / 2)
    // Painted length of each arc: ~1/6 of the circle, centred on the
    // outer side of the bar end. The coloured fill grows from the lower
    // end upwards; the grey track covers the remainder up to the top end.
    readonly property real span: Math.PI / 3
    // Stroke centreline radius: configured arc radius + clearance + half
    // the stroke, so the inner edge clears the island by cfg.margin.
    readonly property real centerRadius: root.cfg.radius + root.cfg.margin + root.cfg.thickness / 2
    // Soft black halo behind the strokes (no hard outer edge): layered
    // translucent passes, spread from config, peak alpha from theme.
    // (Canvas shadow* properties exist but Qt renders nothing for them,
    // verified Sep 2026 — hence strokes.) The box fits the widest pass
    // (+1 AA margin) so the halo is never clipped.
    readonly property real glowWidth: root.cfg.glowWidth ?? 12
    readonly property real box: (root.centerRadius + (root.cfg.thickness + root.glowWidth) / 2 + 1) * 2
    // Half-size: used by the Island to keep the layer surface tall enough.
    readonly property real extent: root.box / 2

    // Hide = slide under the bar (spec): 0 shown, 1 tucked. Both arcs move
    // inwards behind the island ends (z below the body) and fade on the same
    // timed animation, so they visibly sink under the bar instead of just
    // vanishing; showing replays it in reverse (they slide out from under
    // the bar). NOT a spring (user decision, overrides the springs-only
    // rule): timed hideMs/showMs read better here. Duration/easing are set
    // imperatively (onVisibleInStateChanged) BEFORE the value changes, so
    // the Behavior always starts with the right curve.
    property real hideProgress: 0
    readonly property bool hiding: !visibleInState
    // Disabled until Component.onCompleted seeds the initial value: the shell
    // starts in Minimal, and animating 0 -> 1 there would flash the arcs.
    Behavior on hideProgress {
        id: hideBehavior
        enabled: false
        NumberAnimation { id: hideAnim }
    }

    // Bar geometry frozen at the moment of hiding: the island itself springs
    // (with overshoot) into Minimal/module size, and arcs glued to the live
    // edges copied that bounce (out, then back). While hiding they move
    // relative to the island CENTRE (fixed: the island is anchor-centred)
    // using the frozen bar size; showing tracks the live geometry as before.
    property real frozenW: 0
    property real frozenEnd: 0
    readonly property real effW: hiding ? frozenW : root.width
    readonly property real effEnd: hiding ? frozenEnd : root.endCenter

    // Emitted once per hide when the tuck progress reaches cfg.collapseAt:
    // the island holds the bar until then, then collapses into Minimal.
    // 1 - collapseAt is the overlap between the tuck and the collapse.
    signal tucked
    property bool tuckedSent: false
    onHideProgressChanged: {
        if (root.hiding && !root.tuckedSent && root.hideProgress >= (root.cfg.collapseAt ?? 0.5)) {
            root.tuckedSent = true;
            root.tucked();
        }
    }

    onVisibleInStateChanged: {
        root.tuckedSent = false;
        if (!visibleInState) {
            root.frozenW = root.width;
            root.frozenEnd = root.endCenter;
            hideAnim.duration = root.cfg.hideMs ?? 260;
            hideAnim.easing.type = Easing.InOutCubic;
            root.hideProgress = 1;
        } else {
            hideAnim.duration = root.cfg.showMs ?? 420;
            // Slight outward overshoot, like the spring it replaced.
            hideAnim.easing.type = Easing.OutBack;
            root.hideProgress = 0;
        }
    }
    Component.onCompleted: {
        root.frozenW = root.width;
        root.frozenEnd = root.endCenter;
        root.hideProgress = visibleInState ? 0 : 1;
        hideBehavior.enabled = true;
    }

    // Inward travel: the outer crescent (incl. halo) sticking out past the
    // bar end, so a fully tucked arc sits behind the end rounding.
    readonly property real tuckTravel: Math.max(0, root.centerRadius + (root.cfg.thickness + root.glowWidth) / 2 - root.effEnd)
    readonly property real p: Math.max(0, Math.min(1, root.hideProgress))

    // Arc centre offset from the island centre (mirrored for left/right).
    // Hiding: tuck inwards from the frozen bar end, but NEVER further out
    // than the live island end rounding — once the island collapses (from
    // arcs.collapseAt) the arcs are pulled in with it instead of being left
    // outside or drifting away. Showing keeps the unclamped formula (its
    // OutBack overshoot pushes them slightly outwards on purpose).
    readonly property real liveDx: root.width / 2 - root.endCenter
    readonly property real tuckDx: root.effW / 2 - root.effEnd - root.hideProgress * root.tuckTravel
    readonly property real arcDx: hiding ? Math.min(root.tuckDx, root.liveDx) : root.tuckDx

    // Hiding: fade out fast (gone by half the travel) and shrink hard (to
    // ~5%). Showing: the original slower fade-in and 30% → 100% grow.
    // Hiding (tuck or sink) stays visible most of the way and fades as it
    // arrives (1 - p²), shrinking gradually: it must be SEEN going under.
    // The old fast fade (gone by p 0.5) masked an overshoot that the frozen
    // geometry has since fixed — it only made the tuck look instant.
    readonly property real tuckScale: hiding ? 1 - 0.9 * p : 1 - 0.7 * p
    opacity: hiding ? 1 - p * p : 1 - p
    visible: opacity > 0.01

    Item {
        id: leftGroup
        width: root.box
        height: root.box
        x: root.width / 2 - root.arcDx - width / 2
        scale: root.tuckScale
        // Vertically always on the LIVE island centre (frozen geometry is
        // horizontal only — that is where the island's bounce showed).
        y: (root.height - height) / 2

        Canvas {
            id: leftArc
            anchors.fill: parent
            visible: root.network.wifiConnected
            onVisibleChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.lineCap = "round";
                const r = root.centerRadius;
                const cx = width / 2, cy = height / 2;
                const p = Math.max(0, Math.min(1, root.network.wifiStrength / 100));
                // The round caps bridge one thickness worth of angle, the
                // rest stays a visible hairline gap (DashProgress pattern).
                const gap = (root.cfg.thickness / r) * 1.75;
                const spanStart = Math.PI * 5 / 6, spanEnd = Math.PI * 7 / 6;
                const valueEnd = spanStart + p * root.span;
                // Soft black halo (outer → inner passes): rgba() keeps
                // the theme alpha (a direct string cast would drop it).
                const haloWL = root.cfg.glowWidth ?? 12;
                const glowL = root.theme.arcGlow;
                const glowAL = (glowL && glowL.a !== undefined) ? glowL.a : 0.4;
                for (let hi = 0; hi < 4; ++hi) {
                    const tL = hi / 3;
                    ctx.lineWidth = root.cfg.thickness + 2 + (haloWL - 2) * (1 - tL);
                    ctx.strokeStyle = "rgba(0,0,0," + (glowAL * (0.25 + 0.65 * tL)).toFixed(3) + ")";
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, spanStart, spanEnd, false);
                    ctx.stroke();
                }
                ctx.lineWidth = root.cfg.thickness;
                // Grey track: from the fill end up to the top of the arc.
                if (spanEnd - (valueEnd + gap) > 0.01) {
                    ctx.strokeStyle = root.theme.arcTrack;
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, valueEnd + gap, spanEnd, false);
                    ctx.stroke();
                }
                // Coloured fill: from the bottom upwards.
                if (p > 0.005) {
                    ctx.strokeStyle = root.theme.accentYellow;
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, spanStart, valueEnd, false);
                    ctx.stroke();
                }
            }
            Connections {
                target: root.network
                function onWifiStrengthChanged() { leftArc.requestPaint(); }
                function onWifiConnectedChanged() { leftArc.requestPaint(); }
            }
            Connections {
                target: root
                function onGlowWidthChanged() { leftArc.requestPaint(); }
            }
            Connections {
                target: root.theme
                function onArcGlowChanged() { leftArc.requestPaint(); }
            }
        }
    }

    Item {
        id: rightGroup
        width: root.box
        height: root.box
        x: root.width / 2 + root.arcDx - width / 2
        scale: root.tuckScale
        // Vertically always on the LIVE island centre (frozen geometry is
        // horizontal only — that is where the island's bounce showed).
        y: (root.height - height) / 2

        Canvas {
            id: rightArc
            anchors.fill: parent
            visible: root.battery.present
            onVisibleChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.lineCap = "round";
                const r = root.centerRadius;
                const cx = width / 2, cy = height / 2;
                const level = Math.max(0, Math.min(1, root.battery.percent / 100));
                const p = level + (1 - level) * root.wipe;
                // The round caps bridge one thickness worth of angle, the
                // rest stays a visible hairline gap (DashProgress pattern).
                const gap = (root.cfg.thickness / r) * 1.75;
                const spanStart = Math.PI / 6, spanEnd = -Math.PI / 6;
                const valueEnd = spanStart - p * root.span;
                // Soft black halo (outer → inner passes): rgba() keeps
                // the theme alpha (a direct string cast would drop it).
                const haloWR = root.cfg.glowWidth ?? 12;
                const glowR = root.theme.arcGlow;
                const glowAR = (glowR && glowR.a !== undefined) ? glowR.a : 0.4;
                for (let hj = 0; hj < 4; ++hj) {
                    const tR = hj / 3;
                    ctx.lineWidth = root.cfg.thickness + 2 + (haloWR - 2) * (1 - tR);
                    ctx.strokeStyle = "rgba(0,0,0," + (glowAR * (0.25 + 0.65 * tR)).toFixed(3) + ")";
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, spanStart, spanEnd, true);
                    ctx.stroke();
                }
                ctx.lineWidth = root.cfg.thickness;
                // Grey track: from the fill end up to the top of the arc.
                if ((valueEnd - gap) - spanEnd > 0.01) {
                    ctx.strokeStyle = root.theme.arcTrack;
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, valueEnd - gap, spanEnd, true);
                    ctx.stroke();
                }
                // Coloured fill: from the bottom upwards.
                if (p > 0.005) {
                    ctx.strokeStyle = root.batteryColor;
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, spanStart, valueEnd, true);
                    ctx.stroke();
                }
            }
            Connections {
                target: root.battery
                function onPercentChanged() { rightArc.requestPaint(); }
            }
            Connections {
                target: root
                function onBatteryColorChanged() { rightArc.requestPaint(); }
                function onWipeChanged() { rightArc.requestPaint(); }
                function onGlowWidthChanged() { rightArc.requestPaint(); }
            }
            Connections {
                target: root.theme
                function onArcGlowChanged() { rightArc.requestPaint(); }
            }
        }
    }
}
