import QtQuick
import "../../components"
import "Glyph.js" as G

// Keyboard (Magic Keyboard style): a slim white slab slides up, the keys
// pop in row by row (left to right). Loop: typing — random keys dip and
// light up in the tint.
GlyphBase {
    id: g
    glyphName: "keyboard"

    property real slide: 0
    property real keysIn: 0
    property bool looping: false

    onBegin: slideAnim.start()
    onSlideChanged: if (!keysAnim.running && g.keysIn === 0 && g.slide >= g.p("keysAt", 0.6)) keysAnim.start()
    onKeysInChanged: if (!g.looping && g.keysIn >= 1 - g.handoff) g.looping = true
    Spring { id: slideAnim; target: g; property: "slide"; to: 1; stiffness: g.p("revealStiffness", 6); damp: g.p("slideDamping", 0.55); eps: 0.002 }
    Spring { id: keysAnim; target: g; property: "keysIn"; to: 1; stiffness: g.p("keysStiffness", 4); damp: 1; eps: 0.002 }

    // Key layout (unit coords): two rows of 5, then key | space | key.
    readonly property var keyRects: {
        const out = [];
        const x0 = 0.1, w = 0.8, gap = 0.035, kw = (w - 4 * gap) / 5, kh = 0.09;
        for (const y of [0.37, 0.49])
            for (let c = 0; c < 5; c++)
                out.push([x0 + c * (kw + gap), y, kw, kh]);
        out.push([x0, 0.61, kw, kh]);
        out.push([x0 + kw + gap, 0.61, 3 * kw + 2 * gap, kh]);
        out.push([x0 + 4 * (kw + gap), 0.61, kw, kh]);
        return out;
    }

    Timer {
        running: g.looping
        repeat: true
        interval: g.p("typeMs", 190)
        onTriggered: {
            const k = keys.itemAt(Math.floor(Math.random() * keys.count));
            k?.hit();
            interval = g.p("typeMs", 190) * (0.6 + Math.random() * 0.9);
        }
    }

    Item {
        anchors.fill: parent
        opacity: G.smooth(g.slide * 2)
        transform: [
            Translate { y: g.u(0.3) * (1 - g.slide) },
            Scale { origin.x: g.u(0.5); origin.y: g.u(0.52); xScale: g.p("scale", 1.08); yScale: g.p("scale", 1.08) * g.p("stretchY", 1.15) }
        ]
        GlyphFill {
            path: G.rrect(g.u(0.04), g.u(0.29), g.u(0.92), g.u(0.47), g.u(0.07))
            colorTop: g.deviceTop; colorBottom: g.deviceBottom
            gy1: g.u(0.29); gy2: g.u(0.76)
            sheen: g.sheen
        }
        Repeater {
            id: keys
            model: g.keyRects.length
            delegate: Rectangle {
                id: key
                required property int index
                readonly property var r: g.keyRects[key.index]
                property real lit: 0
                function hit(): void {
                    litAnim.restart();
                }
                // Pops in on its turn of the keysIn sweep.
                readonly property real shown: G.smooth(G.span(g.keysIn, key.index / g.keyRects.length * 0.7, key.index / g.keyRects.length * 0.7 + 0.3))
                x: g.u(key.r[0])
                y: g.u(key.r[1]) + g.u(0.012) * key.lit
                width: g.u(key.r[2])
                height: g.u(key.r[3])
                radius: g.u(0.022)
                scale: key.shown
                color: Qt.tint(Qt.alpha(g.ink, 0.55), Qt.alpha(g.color, key.lit))
                SequentialAnimation {
                    id: litAnim
                    NumberAnimation { target: key; property: "lit"; to: 1; duration: 50 }
                    NumberAnimation { target: key; property: "lit"; to: 0; duration: 260; easing.type: Easing.OutCubic }
                }
            }
        }
    }
}
