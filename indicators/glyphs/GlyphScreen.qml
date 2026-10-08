import QtQuick
import QtQuick.Shapes
import "Glyph.js" as G

// A device screen (phone / tablet / laptop lid), all in pixels:
//   frame  — rounded-rect bezel stroke, drawn along its perimeter (`draw`)
//   screen — the inset glass in the tint, PAINTED bottom-up (`paint`, the
//            charger bolt's fill front)
//   shine  — a diagonal light band sweeping across the glass (0..1 = from
//            the top-left corner to the bottom-right one; outside = hidden)
Item {
    id: s
    property real fx: 0
    property real fy: 0
    property real fw: 10
    property real fh: 10
    property real fr: 2
    property real frameWidth: 1.2
    property real inset: 1.2
    property color frameColor: "#F5F6F8"
    property color screenTop: "#5AA9FF"
    property color screenBottom: "#2A5A9A"
    property real draw: 0
    property real paint: 0
    property real shine: -1

    readonly property real sx: s.fx + s.inset
    readonly property real sy: s.fy + s.inset
    readonly property real sw: s.fw - 2 * s.inset
    readonly property real sh: s.fh - 2 * s.inset
    readonly property real sr: Math.max(0, s.fr - s.inset)
    readonly property var glass: G.rrectPts(s.sx, s.sy, s.sw, s.sh, s.sr, 6)
    readonly property string glassPath: s.paint >= 1 ? G.svg(s.glass, true)
        : G.svg(G.clipY(s.glass, s.sy + s.sh * (1 - Math.max(0, s.paint)), false), true)

    anchors.fill: parent

    GlyphFill {
        path: s.glassPath
        colorTop: s.screenTop; colorBottom: s.screenBottom
        gy1: s.sy; gy2: s.sy + s.sh
    }
    // Shine band over the painted glass.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: s.shine > -0.3 && s.shine < 1.3
        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillGradient: LinearGradient {
                x1: s.sx; y1: s.sy
                x2: s.sx + s.sw; y2: s.sy + s.sh
                GradientStop { position: G.clamp(s.shine - 0.16, 0, 1); color: "transparent" }
                GradientStop { position: G.clamp(s.shine, 0, 1); color: Qt.rgba(1, 1, 1, s.shine >= 0 && s.shine <= 1 ? 0.42 : 0) }
                GradientStop { position: G.clamp(s.shine + 0.16, 0, 1); color: "transparent" }
            }
            PathSvg { path: s.paint > 0 ? s.glassPath : "" }
        }
    }
    GlyphLine {
        path: G.svg(G.trim(G.rrectPts(s.fx, s.fy, s.fw, s.fh, s.fr, 6), s.draw), s.draw >= 1)
        color: s.frameColor
        lineWidth: s.frameWidth
    }
}
