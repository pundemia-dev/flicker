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
    // Straight edges sit on the physical pixel grid and the rim is whole
    // physical pixels: at a fractional scale (1.25) a 1 px line between
    // pixels is smeared over two rows.
    readonly property real dpr: root.targetScreen?.devicePixelRatio || 1
    function snap(v: real): real {
        return Math.round(v * root.dpr) / root.dpr;
    }

    visible: root.touchBar.enabled && (root.internal || root.cfg.screens === "all")
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "flicker-touchbar"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    // Room for the spring overshoot; a height that is whole physical pixels
    // too, so the base (y = height) is on the grid.
    implicitHeight: {
        const need = Math.ceil(root.tabHeight * 1.6) + 4;
        for (let hh = need; hh < need + 8; hh++)
            if (Math.abs(hh * root.dpr - Math.round(hh * root.dpr)) < 1e-6)
                return hh;
        return need;
    }

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
            // centres, radii + d, so the rim stays even all along.
            //
            // Profile of a side, from the screen edge up: suction = a concave
            // cubic from `suctionSpread` px out along the edge (horizontal
            // there) up to `suctionRise` px (vertical there), its control
            // points `suctionStrength` of the way towards the corner where
            // the two tangents cross (0 = a straight chamfer, ~0.55 = an
            // elliptic arc, 1 = pulled tight into the corner). Then the
            // rounding: a convex quarter ellipse from the top of the suction
            // straight into the top edge, `radius` px along the top and the
            // rest of the height up — no rectangle corner in between.
            // Without suction it is a plain rounded corner.
            function geo(d: real): var {
                if (tab.h < 0.3 || tab.curW < 1)
                    return null;
                const h = root.snap(tab.h), b = root.height;
                const r = Math.max(0, Math.min(root.cfg.radius ?? 6, tab.curW / 2));
                const sx = Math.max(0, root.cfg.suctionSpread ?? 8);
                const sy = Math.min(Math.max(0, root.cfg.suctionRise ?? 6), h * 0.95);
                const k = Math.max(0, Math.min(1, root.cfg.suctionStrength ?? 0.55));
                const on = sx > d && sy > 0;
                const ry = on ? h - sy : Math.min(r, h);
                const g = { d, b, r, rx: r + d, ry: ry + d, cy: b - h + ry, top: b - h - d, yb: b - d, pts: null };
                // Left half in x offsets from the tab's left edge; the right
                // half is its mirror (rt - u).
                const l = root.snap(tab.cx - tab.curW / 2), rt = root.snap(tab.cx + tab.curW / 2);
                g.L = u => l + u;
                g.M = u => rt - u;
                if (on) {
                    const p = [-d, b - sy], f = [-sx, g.yb];
                    // Tangent crossing: straight below p on the edge.
                    g.pts = { f, p, c1: [f[0] + k * (p[0] - f[0]), g.yb], c2: [p[0], p[1] + k * (g.yb - p[1])] };
                }
                return g;
            }

            // From the top of the suction (or the side's foot) over the top
            // to the mirrored one: the part without suction.
            function bodySegment(g: var): string {
                const { L, M, rx, ry, r, cy, top, d } = g;
                return ` L ${L(-d)} ${cy} A ${rx} ${ry} 0 0 1 ${L(r)} ${top} L ${M(r)} ${top}`
                    + ` A ${rx} ${ry} 0 0 1 ${M(-d)} ${cy}`;
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
                    + ` C ${M(pts.c2[0])} ${pts.c2[1]} ${M(pts.c1[0])} ${yb} ${M(pts.f[0])} ${b} Z`;
            }

            // Rim: flat translucent grey around the tab itself; along the
            // suction it fades out (from `fadeFrom` of the way from the join
            // to the foot) and runs `tail` px past the foot along the edge.
            readonly property var outline: root.cfg.outline ?? ({})
            // In physical pixels.
            readonly property real rim: (tab.outline.width ?? 1) / root.dpr
            readonly property color rimColor: tab.outline.color ?? "#73a0a0a0"
            readonly property color rimClear: Qt.rgba(tab.rimColor.r, tab.rimColor.g, tab.rimColor.b, 0)
            readonly property var rimGeo: tab.rim > 0 ? tab.geo(tab.rim) : null
            readonly property string rimBody: {
                const g = tab.rimGeo;
                if (!g)
                    return "M 0 0";
                const p = tab.startOf(g);
                return `M ${g.L(p[0])} ${g.b} L ${g.L(p[0])} ${p[1]}` + tab.bodySegment(g)
                    + ` L ${g.M(p[0])} ${g.b} Z`;
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
