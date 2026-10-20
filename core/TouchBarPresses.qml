import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import "../config"

// Touch Bar presses (services/TouchBar): a tab in the bezel colour pushed out
// of the bottom screen edge above each held Touch Bar button, joined to the
// edge by concave fillets so it reads as the bezel bulging (iPhone volume
// keys). Spring out on press, held while the finger stays, spring back on
// release. Only on the built-in display by default (the Touch Bar sits under
// it). No input: the mask is empty, clicks go through.
PanelWindow {
    id: root
    // Not `screen`: that shadows WindowInterface.screen (see Island.qml).
    required property ShellScreen targetScreen
    required property var touchBar
    screen: root.targetScreen

    readonly property var cfg: Config.data.touchBar ?? ({})
    readonly property bool internal: /^(eDP|LVDS|DSI)/.test(root.targetScreen?.name ?? "")
    readonly property real tabHeight: root.cfg.height ?? 12
    readonly property color tabColor: root.cfg.color || Config.data.corners?.color || "#101115"

    visible: root.touchBar.enabled && (root.internal || root.cfg.screens === "all")
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "flicker-touchbar"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    // Room for the spring overshoot.
    implicitHeight: Math.ceil(root.tabHeight * 1.6) + 4

    mask: Region {}

    Repeater {
        model: root.touchBar.presses

        delegate: Item {
            id: tab
            required property bool down
            required property real bx
            required property real bw

            anchors.fill: parent

            // Bar fraction → screen: the bar covers `span` of the screen
            // width, centred, shifted by `offset` (both fractions).
            readonly property real cx: root.width * (0.5 + (root.cfg.offset ?? 0) + (tab.bx - 0.5) * (root.cfg.span ?? 0.72))
            readonly property real fullW: root.cfg.widthMode === "button"
                ? tab.bw * (root.cfg.span ?? 0.72) * root.width
                : (root.cfg.width ?? 64)

            // A tap shorter than minShowMs still pops all the way out.
            Timer {
                id: minHold
                interval: root.cfg.minShowMs ?? 120
            }
            onDownChanged: if (tab.down) minHold.restart()
            Component.onCompleted: {
                if (tab.down)
                    minHold.restart();
                tab.h = tab.target;
            }

            property real h: 0
            readonly property real target: tab.down || minHold.running ? root.tabHeight : 0
            onTargetChanged: tab.h = tab.target
            Behavior on h {
                SpringAnimation {
                    spring: root.cfg.spring ?? 6
                    damping: root.cfg.damping ?? 0.35
                    epsilon: 0.05
                }
            }

            // Squeezed out: narrower while it is still short.
            readonly property real grow: Math.max(0, Math.min(1, tab.h / Math.max(1, root.tabHeight)))
            readonly property real curW: tab.fullW * (1 - (root.cfg.squeeze ?? 0.2) * (1 - tab.grow))

            // Tab geometry with the outline pushed `d` px outwards (d = 0:
            // the fill, d = outline.width: the rim drawn under it): same
            // corner centres and the same join angle, so the rim stays even
            // along the suction too.
            //
            // Suction = a concave cubic from `suctionSpread` px out along the
            // screen edge (horizontal there) up to `suctionRise` px. Above the
            // straight side it climbs onto the corner arc and joins it
            // tangentially at that height, the arc rounding the rest. Its
            // control points sit `suctionStrength` of the way towards the
            // corner where the two tangents cross: 0 = a straight chamfer,
            // ~0.55 = an elliptic arc, 1 = pulled tight into the corner.
            function geo(d: real): var {
                const h = tab.h, w = tab.curW, b = root.height;
                if (h < 0.3 || w < 1)
                    return null;
                const r = Math.max(0, Math.min(root.cfg.radius ?? 6, w / 2, h));
                const sx = Math.max(0, root.cfg.suctionSpread ?? 8);
                const sy = Math.min(Math.max(0, root.cfg.suctionRise ?? 6), h * 0.95);
                const k = Math.max(0, Math.min(1, root.cfg.suctionStrength ?? 0.55));
                const g = { d, b, r, R: r + d, cy: b - h + r, top: b - h - d, yb: b - d, pts: null };
                // Left half in x offsets from the tab's left edge; the right
                // half is its mirror (rt - u).
                const l = tab.cx - w / 2, rt = tab.cx + w / 2;
                g.L = u => l + u;
                g.M = u => rt - u;
                if (sx > 0 && sy > 0 && sx > d) {
                    // Join angle on the arc (0 = still on the straight side).
                    const sin = r > 0 && b - sy < g.cy ? Math.min(0.98, (g.cy - (b - sy)) / r) : 0;
                    const cos = Math.sqrt(1 - sin * sin);
                    const p = sin > 0 ? [r - g.R * cos, g.cy - g.R * sin] : [-d, b - sy];
                    if (p[1] < g.yb) {
                        // Crossing of the edge with the tangent at p.
                        const x = [p[0] - (g.yb - p[1]) * sin / cos, g.yb];
                        const f = [Math.min(-sx, x[0]), g.yb];
                        g.pts = { f, p, onArc: sin > 0,
                            c1: [f[0] + k * (x[0] - f[0]), g.yb],
                            c2: [p[0] + k * (x[0] - p[0]), p[1] + k * (x[1] - p[1])] };
                    }
                }
                return g;
            }

            // From the join point (or the side's foot) over the top to the
            // mirrored one: the part without suction.
            function bodySegment(g: var): string {
                const { L, M, R, r, cy, top, d, pts } = g;
                let s = pts && pts.onArc ? "" : ` L ${L(-d)} ${cy}`;
                s += ` A ${R} ${R} 0 0 1 ${L(r)} ${top} L ${M(r)} ${top}`;
                s += pts && pts.onArc ? ` A ${R} ${R} 0 0 1 ${M(pts.p[0])} ${pts.p[1]}`
                    : ` A ${R} ${R} 0 0 1 ${M(-d)} ${cy}`;
                return s;
            }
            function startOf(g: var): var {
                return g.pts ? g.pts.p : [-g.d, g.b];
            }

            readonly property string fillPath: {
                const g = tab.geo(0);
                if (!g)
                    return "M 0 0";
                const { L, M, b, yb, pts } = g;
                if (!pts)
                    return `M ${L(0)} ${b}` + tab.bodySegment(g) + ` L ${M(0)} ${b} Z`;
                return `M ${L(pts.f[0])} ${b} C ${L(pts.c1[0])} ${yb} ${L(pts.c2[0])} ${pts.c2[1]} ${L(pts.p[0])} ${pts.p[1]}`
                    + tab.bodySegment(g)
                    + (pts.onArc ? "" : ` L ${M(pts.p[0])} ${pts.p[1]}`)
                    + ` C ${M(pts.c2[0])} ${pts.c2[1]} ${M(pts.c1[0])} ${yb} ${M(pts.f[0])} ${b} Z`;
            }

            // Rim: flat translucent grey around the tab itself; along the
            // suction it fades out (from `fadeFrom` of the way from the join
            // to the foot) and runs `tail` px past the foot along the edge.
            readonly property var outline: root.cfg.outline ?? ({})
            readonly property real rim: tab.outline.width ?? 1
            readonly property color rimColor: tab.outline.color ?? "#73a0a0a0"
            readonly property color rimClear: Qt.rgba(tab.rimColor.r, tab.rimColor.g, tab.rimColor.b, 0)
            readonly property var rimGeo: tab.rim > 0 ? tab.geo(tab.rim) : null
            readonly property string rimBody: {
                const g = tab.rimGeo;
                if (!g)
                    return "M 0 0";
                const p = tab.startOf(g);
                return `M ${g.L(p[0])} ${g.b} L ${g.L(p[0])} ${p[1]}` + tab.bodySegment(g)
                    + (g.pts && !g.pts.onArc ? ` L ${g.M(p[0])} ${p[1]}` : "") + ` L ${g.M(p[0])} ${g.b} Z`;
            }
            function rimSide(X: var): string {
                const g = tab.rimGeo, pts = g?.pts;
                if (!pts)
                    return "M 0 0";
                const end = pts.f[0] - (tab.outline.tail ?? 10);
                return `M ${X(end)} ${g.b} L ${X(end)} ${g.yb} L ${X(pts.f[0])} ${g.yb}`
                    + ` C ${X(pts.c1[0])} ${g.yb} ${X(pts.c2[0])} ${pts.c2[1]} ${X(pts.p[0])} ${pts.p[1]}`
                    + ` L ${X(pts.p[0])} ${g.b} Z`;
            }
            // Fade span in left offsets: [start, end].
            readonly property var fade: {
                const pts = tab.rimGeo?.pts;
                if (!pts)
                    return [0, 1];
                const k = Math.max(0, Math.min(1, tab.outline.fadeFrom ?? 0.5));
                return [pts.p[0] + (pts.f[0] - pts.p[0]) * k, pts.f[0] - (tab.outline.tail ?? 10)];
            }

            // Opacity, never `visible` (a CurveRenderer Shape toggled via
            // `visible` never repaints again).
            Shape {
                anchors.fill: parent
                opacity: tab.h < 0.3 ? 0 : 1
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: tab.rimColor
                    strokeColor: "transparent"
                    strokeWidth: 0
                    PathSvg { path: tab.rimBody }
                }
                // Suction rims, left and right: fading out past the foot.
                ShapePath {
                    strokeColor: "transparent"
                    strokeWidth: 0
                    fillGradient: LinearGradient {
                        y1: 0
                        y2: 0
                        x1: tab.rimGeo ? tab.rimGeo.L(tab.fade[0]) : 0
                        x2: tab.rimGeo ? tab.rimGeo.L(tab.fade[1]) : 1
                        GradientStop { position: 0; color: tab.rimColor }
                        GradientStop { position: 1; color: tab.rimClear }
                    }
                    PathSvg { path: tab.rimGeo ? tab.rimSide(tab.rimGeo.L) : "M 0 0" }
                }
                ShapePath {
                    strokeColor: "transparent"
                    strokeWidth: 0
                    fillGradient: LinearGradient {
                        y1: 0
                        y2: 0
                        x1: tab.rimGeo ? tab.rimGeo.M(tab.fade[0]) : 0
                        x2: tab.rimGeo ? tab.rimGeo.M(tab.fade[1]) : 1
                        GradientStop { position: 0; color: tab.rimColor }
                        GradientStop { position: 1; color: tab.rimClear }
                    }
                    PathSvg { path: tab.rimGeo ? tab.rimSide(tab.rimGeo.M) : "M 0 0" }
                }
                ShapePath {
                    fillColor: root.tabColor
                    strokeColor: "transparent"
                    strokeWidth: 0
                    PathSvg { path: tab.fillPath }
                }
            }
        }
    }
}
