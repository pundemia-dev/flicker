import QtQuick
import "../../components"

// Motion of the stolen island background, in GLOBAL logical px (all screens
// share one coordinate space; every overlay renders it shifted by its own
// screen origin, so the square crosses monitors seamlessly).
//   launch(): the island rect morphs into the rounded square (size/radius
//   springs) while it flies along an arc (quadratic bezier, spring-driven
//   progress) to the chase point; on landing it switches to chasing: the
//   centre springs after the chase point (cursor + offset, right-below),
//   which gives the lagging, accelerating pursuit.
// Fades (dim, crosshair, square) are timed, per the blur->fade rule.
Item {
    id: root
    required property var cfg

    // Cursor (global) and whether a real pointer position arrived yet.
    property real cursorX: 0
    property real cursorY: 0
    readonly property real targetX: cursorX + cfg.chaseOffsetX
    readonly property real targetY: cursorY + cfg.chaseOffsetY

    // Stolen square: centre + size/radius.
    property real fromX: 0
    property real fromY: 0
    property real w: 0
    property real h: 0
    property real r: 0
    property real flight: 0
    property bool chasing: false
    readonly property bool flying: flightAnim.running

    // Arc control point: between the chord midpoint and the corner
    // (target.x, from.y) — the square leaves the island sideways and
    // curves down onto the cursor.
    readonly property real ctrlX: (fromX + targetX) / 2 + (targetX - (fromX + targetX) / 2) * cfg.arcBend
    readonly property real ctrlY: (fromY + targetY) / 2 + (fromY - (fromY + targetY) / 2) * cfg.arcBend

    function bezier(a: real, c: real, b: real, t: real): real {
        const u = 1 - t;
        return u * u * a + 2 * u * t * c + t * t * b;
    }

    // While flying the chase point is followed instantly (behaviour off),
    // so at the hand-over chaseX == bezier(1) and the spring takes over
    // without a jump.
    property real chaseX: targetX
    property real chaseY: targetY
    Behavior on chaseX {
        enabled: root.chasing
        SpringAnimation { spring: root.cfg.chaseSpring; damping: root.cfg.chaseDamping; mass: root.cfg.chaseMass; epsilon: 0.2 }
    }
    Behavior on chaseY {
        enabled: root.chasing
        SpringAnimation { spring: root.cfg.chaseSpring; damping: root.cfg.chaseDamping; mass: root.cfg.chaseMass; epsilon: 0.2 }
    }

    readonly property real centerX: chasing ? chaseX : bezier(fromX, ctrlX, targetX, flight)
    readonly property real centerY: chasing ? chaseY : bezier(fromY, ctrlY, targetY, flight)

    // Timed fade levels 0..1.
    property real dimLevel: 0
    property real crossLevel: 0
    property real squareLevel: 0
    Behavior on dimLevel { NumberAnimation { duration: root.dimLevel > 0 ? root.cfg.fadeOutMs : root.cfg.fadeInMs } }
    Behavior on crossLevel { NumberAnimation { duration: root.cfg.fadeInMs } }
    Behavior on squareLevel { NumberAnimation { duration: root.cfg.fadeOutMs } }

    function reset(): void {
        flightAnim.stop();
        chasing = false;
        flight = 0;
        squareLevel = 0;
    }

    // rect: global {x, y, width, height, radius} of the island at the steal.
    function launch(rect: var): void {
        reset();
        fromX = rect.x + rect.width / 2;
        fromY = rect.y + rect.height / 2;
        // The square appears exactly over the hidden island: no fade-in.
        squareLevelSnap.start();
        sizeAnimW.from = rect.width;
        sizeAnimH.from = rect.height;
        sizeAnimR.from = rect.radius;
        sizeAnimW.restart();
        sizeAnimH.restart();
        sizeAnimR.restart();
        flightAnim.restart();
    }

    PropertyAction { id: squareLevelSnap; target: root; property: "squareLevel"; value: 1 }

    Spring { id: sizeAnimW; target: root; property: "w"; to: root.cfg.squareSize }
    Spring { id: sizeAnimH; target: root; property: "h"; to: root.cfg.squareSize }
    Spring { id: sizeAnimR; target: root; property: "r"; to: root.cfg.squareRadius }

    SpringAnimation {
        id: flightAnim
        target: root
        property: "flight"
        from: 0
        to: 1
        spring: root.cfg.flightSpring
        damping: root.cfg.flightDamping
        epsilon: 0.002
        onFinished: root.chasing = true
    }
}
