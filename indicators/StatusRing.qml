import QtQuick
import QtQuick.Shapes
import "../components"

// The status drop's ring (services/Statuses): the shown status's arc from
// the top, clockwise, over a track tinted by its colour (only the
// remainder — the track has ends, so its turn is seen). Indeterminate
// statuses spin a fixed-length arc. Switching status (swipe on the drop,
// or a higher priority arriving) = ONE spring driver `k` 0 → 1: the whole
// ring turns round once (the track recolours on the way), the old arc
// squeezes into its start and the new one grows out of that same start.
// `shown` draws everything in / out (`reveal`).
Item {
    id: root
    property var statuses: null
    property var theme: null
    property var cfg: null
    property var entry: null
    property bool shown: false
    // 1 = open, 0 = shut: driven by the drop's way back into the island
    // (Island), so the ring is closed BEFORE the drop merges (user).
    property real squeeze: 1
    property real line: root.cfg?.ringLine ?? 2.5

    readonly property string key: root.entry?.key ?? ""
    property var prev: null
    property int dir: 1
    property real k: 1
    property real spinAtSwap: 0
    Behavior on k {
        id: kBehavior
        Spring {
            stiffness: root.cfg?.swapStiffness ?? 2.2
            damp: root.cfg?.swapDamping ?? 0.32
            eps: 0.002
        }
    }
    // Last entry per key (entries are replaced in place on every update).
    property var held: null
    onEntryChanged: {
        const old = root.held;
        // Only a switch on a visible ring animates (a status arriving after
        // the ring was gone just draws in).
        if (root.entry && old && old.key !== root.entry.key && root.reveal > 0.05) {
            root.prev = old;
            root.dir = root.statuses?.lastDir ?? 1;
            root.spinAtSwap = root.spin;
            kBehavior.enabled = false;
            root.k = 0;
            kBehavior.enabled = true;
            root.k = 1;
        }
        if (root.entry)
            root.held = root.entry;
    }
    onKChanged: if (root.k >= 0.999 && Math.abs(root.k - 1) < 0.002) root.prev = null

    // Draws in on the reveal* spring; closes on the faster revealOut* one
    // (user: while the drop is sucked back the ring must be shut first).
    property real reveal: root.shown ? 1 : 0
    Behavior on reveal {
        Spring {
            stiffness: root.shown ? (root.cfg?.revealStiffness ?? 3) : (root.cfg?.revealOutStiffness ?? 14)
            damp: root.shown ? (root.cfg?.revealDamping ?? 0.6) : (root.cfg?.revealOutDamping ?? 0.45)
            eps: 0.002
        }
    }

    // Live values (functions are re-read inside these bindings).
    readonly property var pNew: root.statuses?.progressOf(root.held) ?? null
    readonly property var pOld: root.prev ? (root.statuses?.progressOf(root.prev) ?? null) : null
    readonly property bool newIndet: root.held !== null && root.pNew === null
    readonly property bool oldIndet: root.prev !== null && root.pOld === null
    function tone(st: var): color {
        const name = root.statuses?.colorOf(st) ?? "islandFg";
        return root.theme?.[name] ?? "#FFFFFF";
    }
    readonly property color cNew: root.tone(root.held)
    readonly property color cOld: root.prev ? root.tone(root.prev) : root.cNew

    // Indeterminate spin: a running angle (a loop, not a transition).
    property real spin: 0
    FrameAnimation {
        running: (root.newIndet || root.oldIndet) && root.reveal > 0.01
        onTriggered: root.spin = (root.spin + frameTime * (root.cfg?.spinDegPerSec ?? 300)) % 360
    }

    function clamp01(v: real): real {
        return Math.max(0, Math.min(1, v));
    }
    readonly property real kc: root.clamp01(root.k)
    readonly property real indetLen: 360 * (root.cfg?.indeterminate ?? 0.28)
    readonly property real open: root.clamp01(root.reveal) * root.clamp01(root.squeeze)
    readonly property real lenNew: (root.newIndet ? root.indetLen : 360 * (root.pNew ?? 0))
        * (root.prev ? root.clamp01((root.k - 0.4) / 0.6) : 1) * root.open
    readonly property real lenOld: root.prev
        ? (root.oldIndet ? root.indetLen : 360 * (root.pOld ?? 0)) * (1 - root.clamp01(root.k / 0.6)) * root.open : 0
    readonly property real base: -90 + (root.prev ? root.dir * 360 * root.k : 0)
        + (root.newIndet ? root.spin : 0) * (root.prev ? root.kc : 1)
        + (root.oldIndet ? root.spinAtSwap * (1 - root.kc) : 0)

    readonly property real radius: Math.max(0, (Math.min(root.width, root.height) - root.line) / 2)
    // Gap between an arc's round cap and the track (degrees).
    readonly property real capGap: root.radius > 0 ? root.line * 1.6 / root.radius * 180 / Math.PI : 0
    readonly property real lenMax: Math.max(root.lenNew, root.lenOld)
    readonly property real trackA: root.cfg?.trackAlpha ?? 0.28
    readonly property color trackColor: {
        const a = root.cOld, b = root.cNew, t = root.prev ? root.kc : 1;
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t,
            root.trackA * root.open);
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        // Track: the remainder after the longer arc (a full circle without one).
        ShapePath {
            strokeColor: root.trackColor
            strokeWidth: root.line
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: root.radius
                radiusY: root.radius
                startAngle: root.lenMax < 0.5 ? root.base : root.base + root.lenMax + root.capGap
                sweepAngle: root.lenMax < 0.5 ? 360 : Math.max(0, 360 - root.lenMax - 2 * root.capGap)
            }
        }
        ShapePath {
            strokeColor: root.lenOld < 0.5 ? "transparent" : root.cOld
            strokeWidth: root.line
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: root.radius
                radiusY: root.radius
                startAngle: root.base
                sweepAngle: Math.max(0.01, root.lenOld)
            }
        }
        ShapePath {
            strokeColor: root.lenNew < 0.5 ? "transparent" : root.cNew
            strokeWidth: root.line
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: root.radius
                radiusY: root.radius
                startAngle: root.base
                sweepAngle: Math.max(0.01, root.lenNew)
            }
        }
    }
}
