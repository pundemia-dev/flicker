import QtQuick
import QtQuick.Shapes
import "../config"
import "VolumeGeometry.js" as G

// Shape-built volume glyph (OSD, player, QS media card): speaker = rectangle
// rounded on the left + cone trapezoid with rounded acute corners, up to
// three arcs to its right. Timed eased animations (user decision — an
// exception to the Spring-only rule), except the mute slash (spring):
//  - `arcs` (0..3): each arc fades in/out on its own animation; the content
//    stays centred in the box, so the speaker slides as space frees up;
//  - `muted`: a slash draws from the top-left to the bottom-right corner,
//    cutting a sharp-edged gap (no rounding) through whatever it crosses;
//  - pulse(): the whole icon grows and shrinks back once;
//  - wave(): the speaker pulses, then each arc in turn, outward (arcs
//    scale about their common centre, i.e. push away from the speaker).
// `maxArcs` reserves the box width (0 = a bare speaker).
Item {
    id: root
    property real size: 22
    property color color: "#DFE6F2"
    property int arcs: 3
    property int maxArcs: 3
    property bool muted: false

    readonly property var cfg: Config.data.volumeIcon

    implicitHeight: size
    implicitWidth: G.contentWidth([1, 1, 1], maxArcs) * size

    function pulse(): void {
        pulseAnim.restart();
    }
    function wave(): void {
        waveAnim.restart();
    }

    // Arc visibilities, slash progress, pulse/wave scales.
    property real vis0: root.arcs > 0 && root.maxArcs > 0 ? 1 : 0
    property real vis1: root.arcs > 1 && root.maxArcs > 1 ? 1 : 0
    property real vis2: root.arcs > 2 && root.maxArcs > 2 ? 1 : 0
    property real slashP: root.muted ? 1 : 0
    property real pulseScale: 1
    property real bodyScale: 1
    property real arcScale0: 1
    property real arcScale1: 1
    property real arcScale2: 1
    Behavior on vis0 { NumberAnimation { duration: root.cfg.arcFadeMs; easing.type: Easing.InOutCubic } }
    Behavior on vis1 { NumberAnimation { duration: root.cfg.arcFadeMs; easing.type: Easing.InOutCubic } }
    Behavior on vis2 { NumberAnimation { duration: root.cfg.arcFadeMs; easing.type: Easing.InOutCubic } }
    Behavior on slashP { Spring { stiffness: root.cfg.slashStiffness; damp: root.cfg.slashDamping; eps: 0.002 } }

    // Content width (centring + slash box) follows the TARGET arc count on
    // its own, longer and softer animation — the shift no longer rides the
    // arcs' fade curve.
    property real contentW: G.contentWidth([root.arcs > 0 ? 1 : 0, root.arcs > 1 ? 1 : 0, root.arcs > 2 ? 1 : 0], maxArcs) * size
    Behavior on contentW { NumberAnimation { duration: root.cfg.shiftMs; easing.type: Easing.InOutSine } }

    readonly property var geo: {
        const S = root.size;
        const sl = G.slash(S, root.contentW);
        const body = G.scaled(G.bodyPoly(S), { x: G.SPEAKER_RIGHT * S / 2, y: S / 2 }, root.bodyScale);
        const sc = [root.arcScale0, root.arcScale1, root.arcScale2];
        const arcs = [];
        for (let i = 0; i < Math.min(3, root.maxArcs); i++)
            arcs.push(G.cut(G.scaled(G.arcPoly(S, i), G.arcCenter(S), sc[i]), sl, root.slashP, S));
        return { slash: sl, body: G.cut(body, sl, root.slashP, S), arcs: arcs };
    }

    function ink(a: real): color {
        return Qt.rgba(root.color.r, root.color.g, root.color.b, root.color.a * Math.max(0, Math.min(1, a)));
    }

    // One element (speaker or an arc) = the cut pieces as one path (they
    // never overlap, see VolumeGeometry.js).
    component Glyph: Shape {
        id: glyph
        property var pieces: []
        property real alpha: 1
        anchors.fill: parent
        // NO visible toggling (alpha 0 = transparent ink instead): a
        // CurveRenderer Shape hidden via `visible` never repainted after
        // being shown again — arcs gone for good once the volume hit 0.
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: root.ink(glyph.alpha)
            strokeColor: "transparent"
            PathMultiline { paths: glyph.pieces }
        }
    }

    Item {
        id: content
        x: (root.width - root.contentW) / 2
        anchors.verticalCenter: parent.verticalCenter
        width: root.contentW
        height: root.size
        scale: root.pulseScale

        Glyph {
            pieces: root.geo.body
        }
        Glyph {
            pieces: root.geo.arcs[0] ?? []
            alpha: root.vis0
        }
        Glyph {
            pieces: root.geo.arcs[1] ?? []
            alpha: root.vis1
        }
        Glyph {
            pieces: root.geo.arcs[2] ?? []
            alpha: root.vis2
        }

        // The slash itself: grows from the top-left corner (retracts back
        // on unmute); fades in over its first few percent so it never
        // pops in as a dot (opacity, not `visible` — see Glyph).
        Shape {
            anchors.fill: parent
            opacity: Math.pow(Math.min(1, root.slashP * 4), 2)
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                id: slashPath
                readonly property var sl: root.geo.slash
                readonly property real p: Math.max(0, Math.min(1, root.slashP))
                fillColor: "transparent"
                strokeColor: root.color
                strokeWidth: sl.w
                capStyle: ShapePath.RoundCap
                startX: sl.ax
                startY: sl.ay
                PathLine {
                    x: slashPath.sl.ax + slashPath.sl.dx * slashPath.sl.len * slashPath.p
                    y: slashPath.sl.ay + slashPath.sl.dy * slashPath.sl.len * slashPath.p
                }
            }
        }
    }

    component Bump: SequentialAnimation {
        id: bump
        property string prop
        property real peak: 1.2
        property int delay: 0
        PauseAnimation { duration: bump.delay }
        NumberAnimation {
            target: root
            property: bump.prop
            to: bump.peak
            duration: root.cfg.bumpUpMs
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: bump.prop
            to: 1
            duration: root.cfg.bumpDownMs
            easing.type: Easing.InOutCubic
        }
    }

    Bump {
        id: pulseAnim
        prop: "pulseScale"
        peak: root.cfg.pulseScale
    }
    ParallelAnimation {
        id: waveAnim
        Bump { prop: "bodyScale"; peak: root.cfg.waveScale }
        Bump { prop: "arcScale0"; peak: root.cfg.waveScale; delay: root.cfg.waveStaggerMs }
        Bump { prop: "arcScale1"; peak: root.cfg.waveScale; delay: root.cfg.waveStaggerMs * 2 }
        Bump { prop: "arcScale2"; peak: root.cfg.waveScale; delay: root.cfg.waveStaggerMs * 3 }
    }
}
