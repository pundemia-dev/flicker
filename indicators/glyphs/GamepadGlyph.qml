import QtQuick
import "../../components"
import "Glyph.js" as G

// Gamepad: a white controller body with two grips, a d-pad on the left
// and four face buttons on the right. Reveal: pops in from the centre on a
// bouncy spring. Loop: the face buttons light up in turn (tint) and the pad
// tilts left / right as if steering.
GlyphBase {
    id: g
    glyphName: "gamepad"

    property real pop: 0
    property real tilt: 0
    property int litButton: -1
    property bool looping: false

    onBegin: popAnim.start()
    onPopChanged: if (!g.looping && g.pop >= 1 - g.handoff) g.looping = true
    Spring { id: popAnim; target: g; property: "pop"; to: 1; stiffness: g.p("popStiffness", 7); damp: g.p("popDamping", 0.45); eps: 0.002 }
    Behavior on tilt { Spring { stiffness: g.p("tiltStiffness", 4); damp: 0.4; eps: 0.002 } }
    Timer {
        running: g.looping
        repeat: true
        interval: g.p("buttonMs", 320)
        onTriggered: g.litButton = (g.litButton + 1) % 4
    }
    Timer {
        running: g.looping
        repeat: true
        interval: g.p("loopMs", 1800) * 0.6
        onTriggered: g.tilt = g.tilt > 0 ? -1 : 1
    }

    Item {
        anchors.fill: parent
        opacity: G.smooth(g.pop * 2.5)
        transform: [
            Scale { origin.x: g.u(0.5); origin.y: g.u(0.55); xScale: (0.25 + 0.75 * g.pop) * g.p("scale", 1.2); yScale: (0.25 + 0.75 * g.pop) * g.p("scale", 1.2) },
            Rotation { origin.x: g.u(0.5); origin.y: g.u(0.55); angle: g.p("tiltDeg", 7) * g.tilt }
        ]
        // Grips first (under the body), then the body.
        GlyphFill {
            path: G.ellipse(g.u(0.27), g.u(0.6), g.u(0.15), g.u(0.19))
            colorTop: g.deviceTop; colorBottom: g.deviceBottom
            gy1: g.u(0.3); gy2: g.u(0.79)
        }
        GlyphFill {
            path: G.ellipse(g.u(0.73), g.u(0.6), g.u(0.15), g.u(0.19))
            colorTop: g.deviceTop; colorBottom: g.deviceBottom
            gy1: g.u(0.3); gy2: g.u(0.79)
        }
        GlyphFill {
            path: G.rrect(g.u(0.12), g.u(0.3), g.u(0.76), g.u(0.33), g.u(0.16))
            colorTop: g.deviceTop; colorBottom: g.deviceBottom
            gy1: g.u(0.3); gy2: g.u(0.79)
            sheen: g.sheen
        }
        // D-pad.
        GlyphFill {
            path: G.rrect(g.u(0.22), g.u(0.445), g.u(0.15), g.u(0.05), g.u(0.015))
            colorTop: g.ink; colorBottom: g.ink
        }
        GlyphFill {
            path: G.rrect(g.u(0.27), g.u(0.395), g.u(0.05), g.u(0.15), g.u(0.015))
            colorTop: g.ink; colorBottom: g.ink
        }
        // Face buttons: top, right, bottom, left.
        Repeater {
            model: [[0.7, 0.4], [0.765, 0.47], [0.7, 0.54], [0.635, 0.47]]
            delegate: Rectangle {
                required property var modelData
                required property int index
                width: g.u(0.065)
                height: width
                radius: width / 2
                x: g.u(modelData[0]) - width / 2
                y: g.u(modelData[1]) - height / 2
                color: index === g.litButton ? g.fillTop : g.ink
                Behavior on color { ColorAnimation { duration: 120 } }
            }
        }
    }
}
