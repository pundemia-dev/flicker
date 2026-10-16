import QtQuick
import "../../components"
import "Glyph.js" as G

// USB drive: the stick slides in from the left connector-first and
// "clicks" home (under-damped), its activity LED lights. Loop: the LED
// flickers like reads. `args.eject` (removed): starts home, the LED goes
// out and the stick slides away to the left, fading.
GlyphBase {
    id: g
    glyphName: "drive"

    readonly property bool eject: !!g.args?.eject
    // 0 = away on the left .. 1 = home.
    property real slide: 0
    property real led: 0
    property real flicker: 1
    property bool looping: false

    onBegin: {
        if (g.eject) {
            g.slide = 1;
            g.led = 1;
            ledAnim.to = 0;
            ledAnim.start();
        } else {
            slideAnim.to = 1;
            slideAnim.start();
        }
    }
    onSlideChanged: if (!g.eject && !ledAnim.running && g.led === 0 && g.slide >= g.p("ledAt", 0.9)) {
        ledAnim.to = 1;
        ledAnim.start();
    }
    onLedChanged: {
        if (!g.eject && !g.looping && g.led >= 1 - g.handoff)
            g.looping = true;
        if (g.eject && !slideAnim.running && g.slide === 1 && g.led <= 0.3) {
            slideAnim.to = 0;
            slideAnim.start();
        }
    }
    Spring { id: slideAnim; target: g; property: "slide"; stiffness: g.p("slideStiffness", 5); damp: g.p("slideDamping", 0.4); eps: 0.002 }
    Spring { id: ledAnim; target: g; property: "led"; stiffness: g.p("popStiffness", 7); damp: 1; eps: 0.004 }
    SequentialAnimation on flicker {
        running: g.looping
        loops: Animation.Infinite
        PauseAnimation { duration: g.p("loopMs", 1800) * 0.6 }
        NumberAnimation { to: 0.3; duration: 70 }
        NumberAnimation { to: 1; duration: 90 }
        NumberAnimation { to: 0.4; duration: 60 }
        NumberAnimation { to: 1; duration: 120 }
        PauseAnimation { duration: 140 }
        NumberAnimation { to: 0.35; duration: 70 }
        NumberAnimation { to: 1; duration: 110 }
    }

    Item {
        anchors.fill: parent
        opacity: G.smooth(g.slide * 2.5)
        transform: Translate { x: -g.u(g.p("travel", 0.45)) * (1 - g.slide) }
        // Connector (metal) with its two contact windows.
        GlyphFill {
            path: G.rrect(g.u(0.64), g.u(0.38), g.u(0.29), g.u(0.24), g.u(0.025))
            colorTop: g.deviceTop; colorBottom: g.deviceBottom
            gy1: g.u(0.38); gy2: g.u(0.62)
        }
        GlyphFill {
            path: G.rrect(g.u(0.72), g.u(0.45), g.u(0.06), g.u(0.05), g.u(0.01)) + " " + G.rrect(g.u(0.83), g.u(0.45), g.u(0.06), g.u(0.05), g.u(0.01))
            colorTop: g.ink; colorBottom: g.ink
        }
        // Body in the tint.
        GlyphFill {
            path: G.rrect(g.u(0.06), g.u(0.31), g.u(0.6), g.u(0.38), g.u(0.1))
            colorTop: g.fillTop; colorBottom: g.fillBottom
            gy1: g.u(0.31); gy2: g.u(0.69)
            sheen: g.sheen
        }
        // Activity LED.
        GlyphFill {
            opacity: g.led * g.flicker
            path: G.circle(g.u(0.18), g.u(0.5), g.u(0.045))
            colorTop: "#FFFFFF"; colorBottom: Qt.lighter(g.color, 1.6)
        }
    }
}
