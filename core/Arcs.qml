import QtQuick

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

    opacity: visibleInState ? 1 : 0
    Behavior on opacity {
        NumberAnimation {
            duration: 140
        }
    }

    Item {
        id: leftGroup
        width: root.box
        height: root.box
        x: root.endCenter - width / 2
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
        x: root.width - root.endCenter - width / 2
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
                const p = Math.max(0, Math.min(1, root.battery.percent / 100));
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
                function onGlowWidthChanged() { rightArc.requestPaint(); }
            }
            Connections {
                target: root.theme
                function onArcGlowChanged() { rightArc.requestPaint(); }
            }
        }
    }
}
