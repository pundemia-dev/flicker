import QtQuick
import "../../components"
import "Glyph.js" as G

// External display (Studio Display style): the stand rises, the bezel
// draws along its perimeter and the glass paints bottom-up. Loop: a shine
// sweeps the screen. `args.off` (disconnected): starts lit, the glass
// collapses to a horizontal line and goes out (old-TV switch-off), the
// bezel stays dim.
GlyphBase {
    id: g
    glyphName: "display"

    readonly property bool off: !!g.args?.off
    property real stand: 0
    property real draw: 0
    property real paint: 0
    property real shine: -1
    // Switch-off: 0 lit .. 1 dark.
    property real dark: 0
    property bool looping: false

    onBegin: {
        if (g.off) {
            g.stand = 1;
            g.draw = 1;
            g.paint = 1;
            darkAnim.start();
        } else {
            standAnim.start();
        }
    }
    onStandChanged: if (!g.off && !drawAnim.running && g.draw === 0 && g.stand >= g.p("drawAt", 0.5)) drawAnim.start()
    onDrawChanged: if (!g.off && !paintAnim.running && g.paint === 0 && g.draw >= g.p("paintAt", 0.75)) paintAnim.start()
    onPaintChanged: if (!g.off && !g.looping && g.paint >= 1 - g.handoff) g.looping = true
    Spring { id: standAnim; target: g; property: "stand"; to: 1; stiffness: g.p("popStiffness", 7); damp: g.p("popDamping", 0.5); eps: 0.002 }
    Spring { id: drawAnim; target: g; property: "draw"; to: 1; stiffness: g.p("revealStiffness", 6); damp: 1; eps: 0.002 }
    Spring { id: paintAnim; target: g; property: "paint"; to: 1; stiffness: g.p("revealStiffness", 6); damp: 1; eps: 0.002 }
    Spring { id: darkAnim; target: g; property: "dark"; to: 1; stiffness: g.p("offStiffness", 4); damp: 1; eps: 0.002 }
    SequentialAnimation on shine {
        running: g.looping
        loops: Animation.Infinite
        NumberAnimation { from: -0.2; to: 1.25; duration: g.p("shineMs", 700); easing.type: Easing.InOutSine }
        PauseAnimation { duration: g.p("loopMs", 1800) }
    }

    readonly property real sx: g.u(0.08)
    readonly property real sy: g.u(0.14)
    readonly property real sw: g.u(0.84)
    readonly property real sh: g.u(0.56)

    // Stand: neck + foot, rising from below.
    Item {
        anchors.fill: parent
        opacity: G.smooth(g.stand * 2)
        transform: Translate { y: g.u(0.18) * (1 - g.stand) }
        GlyphFill {
            path: G.rrect(g.u(0.42), g.u(0.66), g.u(0.16), g.u(0.16), g.u(0.02))
            colorTop: Qt.darker(g.deviceBottom, 1.2); colorBottom: g.deviceBottom
        }
        GlyphFill {
            path: G.rrect(g.u(0.3), g.u(0.8), g.u(0.4), g.u(0.06), g.u(0.03))
            colorTop: g.deviceTop; colorBottom: g.deviceBottom
        }
    }
    // Body behind the glass.
    GlyphFill {
        opacity: G.smooth(g.draw * 2)
        path: G.rrect(g.sx, g.sy, g.sw, g.sh, g.u(0.06))
        colorTop: g.deviceTop; colorBottom: g.deviceBottom
        gy1: g.sy; gy2: g.sy + g.sh
    }
    // Switch-off: the glass squeezes vertically to a line, then the line
    // shrinks to nothing.
    Item {
        anchors.fill: parent
        opacity: 1 - G.span(g.dark, 0.75, 1)
        transform: Scale {
            origin.x: g.u(0.5); origin.y: g.sy + g.sh / 2
            yScale: Math.max(0.03, 1 - G.span(g.dark, 0, 0.5))
            xScale: 1 - 0.9 * G.span(g.dark, 0.45, 1)
        }
        GlyphScreen {
            fx: g.sx; fy: g.sy; fw: g.sw; fh: g.sh; fr: g.u(0.06)
            frameWidth: 0
            inset: g.u(0.05)
            frameColor: "transparent"
            screenTop: Qt.tint(g.fillTop, Qt.rgba(1, 1, 1, 0.5 * G.span(g.dark, 0.2, 0.6)))
            screenBottom: g.fillBottom
            draw: 1; paint: g.paint; shine: g.shine
        }
    }
    // Dark glass left behind after the switch-off.
    GlyphFill {
        visible: g.off
        opacity: G.span(g.dark, 0.3, 1)
        path: G.rrect(g.sx + g.u(0.05), g.sy + g.u(0.05), g.sw - g.u(0.1), g.sh - g.u(0.1), g.u(0.02))
        colorTop: g.ink; colorBottom: Qt.lighter(g.ink, 1.6)
    }
}
