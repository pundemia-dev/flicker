import QtQuick
import "../../components"
import "Glyph.js" as G

// AirPods (Apple style, AirPods 3 proportions — user): two white buds
// set wide apart, a big round head with two dark meshes on top and a
// short stem below; heads slightly flattened. Reveal: the buds drop in one
// after another from above, tilted, and settle on a bouncy spring (taken
// out of the case). Loop: they bob gently out of phase (no sound arcs —
// user).
GlyphBase {
    id: g
    glyphName: "airpods"

    property real dropL: 0
    property real dropR: 0
    property real bob: 0
    property bool looping: false

    onBegin: dropLAnim.start()
    onDropLChanged: if (!dropRAnim.running && g.dropR === 0 && g.dropL >= g.p("stagger", 0.45)) dropRAnim.start()
    onDropRChanged: if (!g.looping && g.dropR >= 1 - g.handoff) g.looping = true
    Spring { id: dropLAnim; target: g; property: "dropL"; to: 1; stiffness: g.p("popStiffness", 7); damp: g.p("popDamping", 0.45); eps: 0.002 }
    Spring { id: dropRAnim; target: g; property: "dropR"; to: 1; stiffness: g.p("popStiffness", 7); damp: g.p("popDamping", 0.45); eps: 0.002 }
    SequentialAnimation on bob {
        running: g.looping
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: 1; duration: g.p("bobMs", 900); easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: 0; duration: g.p("bobMs", 900); easing.type: Easing.InOutSine }
    }

    // The two buds (a Repeater delegate sees the file's ids; an inline
    // component would not).
    Repeater {
        model: [-1, 1] // left, right
        delegate: Item {
            id: bud
            required property int modelData
            readonly property int side: bud.modelData
            readonly property real drop: bud.side < 0 ? g.dropL : g.dropR
            // Mirror a unit x for the right bud.
            function mx(x: real): real {
                return bud.side < 0 ? x : 1 - x;
            }
            anchors.fill: parent
            opacity: G.smooth(bud.drop * 2)
            transform: [
                Rotation {
                    origin.x: g.u(bud.mx(0.12)); origin.y: g.u(0.5)
                    angle: bud.side * g.p("dropTilt", 22) * (1 - bud.drop)
                },
                Translate {
                    y: -g.u(0.55) * (1 - bud.drop) + g.u(0.03) * (bud.side < 0 ? g.bob : 1 - g.bob)
                },
                Scale {
                    origin.x: g.u(0.5); origin.y: g.u(0.48)
                    xScale: g.p("scale", 1.1); yScale: g.p("scale", 1.1)
                }
            ]
            // Geometry is laid out for the LEFT bud (stem under the OUTER
            // end of the head, user) and mirrored (x -> 1 - x) for the right one.
            function mirrored(pts: var): var {
                return bud.side < 0 ? pts : pts.map(q => [g.u(1) - q[0], q[1]]);
            }
            // The head: an oval tilted 45 deg — long axis from the lower
            // inner end (over the stem) up toward the outside.
            readonly property real hx: g.u(0.23)
            readonly property real hy: g.u(0.36)
            // + headTurn: the whole head (oval + meshes) turned on its centre
            // relative to the stem — left clockwise, right counter (mirror).
            readonly property real tilt: g.p("headTilt", 35) + g.p("headTurn", 90)
            // Unit normal of the long axis, pointing up (and inward).
            readonly property var up: [Math.sin(bud.tilt * Math.PI / 180), -Math.cos(bud.tilt * Math.PI / 180)]
            GlyphFill {
                path: G.rrect(g.u(Math.min(bud.mx(0.05), bud.mx(0.17))), g.u(0.44), g.u(0.12), g.u(0.35), g.u(0.06))
                // Own gradient per part (pacman / moon look: light top, dark
                // bottom over the part itself) + the sheen.
                colorTop: g.deviceTop; colorBottom: Qt.darker(g.deviceBottom, g.p("shade", 1.12))
                gy1: g.u(0.44); gy2: g.u(0.79)
                sheen: g.sheen
            }
            GlyphFill {
                path: G.rrect(g.u(Math.min(bud.mx(0.05), bud.mx(0.17))), g.u(0.73), g.u(0.12), g.u(0.06), g.u(0.04))
                colorTop: Qt.darker(g.deviceBottom, 1.15); colorBottom: Qt.darker(g.deviceBottom, 1.4)
                gy1: g.u(0.73); gy2: g.u(0.79)
            }
            GlyphFill {
                path: G.svg(bud.mirrored(G.superellipsePts(bud.hx, bud.hy, g.u(0.21), g.u(0.21 * g.p("headSquash", 0.82) * g.p("headLength", 1.45)), bud.tilt, g.p("headCorner", 2.6), 64)), true)
                colorTop: g.deviceTop; colorBottom: Qt.darker(g.deviceBottom, g.p("shade", 1.12))
                gy1: g.u(0.12); gy2: g.u(0.6)
                sheen: g.sheen
            }
            // Two dark meshes: an oval ALONG the tilt (inner), a stadium
            // ACROSS it (outer).
            GlyphFill {
                path: G.svg(bud.mirrored(G.ellipsePts(bud.hx + bud.up[0] * g.u(g.p("meshTop", 0.16)), bud.hy + bud.up[1] * g.u(g.p("meshTop", 0.16)), g.u(0.085 * g.p("meshLowerScale", 1.5) * g.p("meshLowerLength", 0.85)), g.u(0.03 * g.p("meshLowerScale", 1.5)), bud.tilt, 40)), true)
                    + " " + G.svg(bud.mirrored(G.stadiumPts(bud.hx - bud.up[0] * g.u(g.p("meshBottom", 0.13)), bud.hy - bud.up[1] * g.u(g.p("meshBottom", 0.13)), g.u(0.09 * g.p("meshUpperScale", 2)), g.u(0.05 * g.p("meshUpperScale", 2)), bud.tilt + 90)), true)
                colorTop: g.ink; colorBottom: g.ink
            }
        }
    }
}
