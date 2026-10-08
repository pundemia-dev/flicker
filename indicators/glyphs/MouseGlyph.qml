import QtQuick
import QtQuick.Shapes
import "../../components"
import "Glyph.js" as G

// Mouse (Magic Mouse style): a smooth white pebble that slides up into
// place. Loop: a finger tap — the body dips a little and a ring in the
// tint ripples out from the touch point.
GlyphBase {
    id: g
    glyphName: "mouse"

    property real slide: 0
    property real ripple: 0
    property real press: 0
    property bool looping: false

    onBegin: slideAnim.start()
    onSlideChanged: if (!g.looping && g.slide >= 1 - g.handoff) g.looping = true
    Spring { id: slideAnim; target: g; property: "slide"; to: 1; stiffness: g.p("revealStiffness", 6); damp: g.p("slideDamping", 0.55); eps: 0.002 }
    Behavior on press { Spring { stiffness: 9; damp: 0.4; eps: 0.002 } }
    SequentialAnimation {
        running: g.looping
        loops: Animation.Infinite
        PauseAnimation { duration: g.p("loopMs", 1800) * 0.5 }
        ScriptAction { script: g.press = 1 }
        PauseAnimation { duration: 90 }
        ScriptAction { script: g.press = 0 }
        NumberAnimation { target: g; property: "ripple"; from: 0; to: 1; duration: g.p("rippleMs", 650); easing.type: Easing.OutCubic }
        PauseAnimation { duration: g.p("loopMs", 1800) * 0.5 }
    }

    Item {
        anchors.fill: parent
        opacity: G.smooth(g.slide * 2)
        transform: [
            Translate { y: g.u(0.35) * (1 - g.slide) },
            Scale { origin.x: g.u(0.5); origin.y: g.u(0.9); yScale: 1 - 0.05 * g.press; xScale: 1 + 0.02 * g.press }
        ]
        GlyphFill {
            path: G.rrect(g.u(0.29), g.u(0.08), g.u(0.42), g.u(0.84), g.u(0.21))
            colorTop: g.deviceTop; colorBottom: g.deviceBottom
            gy1: g.u(0.08); gy2: g.u(0.92)
            sheen: g.sheen
        }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            opacity: (1 - g.ripple) * (g.ripple > 0 ? 1 : 0)
            ShapePath {
                fillColor: "transparent"
                strokeColor: g.color
                strokeWidth: g.u(0.06)
                PathAngleArc {
                    centerX: g.u(0.5); centerY: g.u(0.32)
                    radiusX: g.u(0.03 + 0.15 * g.ripple); radiusY: g.u(0.03 + 0.15 * g.ripple)
                    startAngle: 0; sweepAngle: 360
                }
            }
        }
    }
}
