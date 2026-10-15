import QtQuick
import QtQuick.Shapes
import "../components"
import "../components/Metaball.js" as Metaball

// The status drop's BODY (z below the island): a circle that lives in the
// island's right end rounding and splits off to the right of the island
// through a metaball neck (components/Metaball.js), then sits there with
// the status ring (Island draws the ring above the island at cx/cy). Modes:
//   "inline"  the status's event shows: the drop stays in the end rounding
//             (the ring shows inside the island's right end)
//   "out"     split off: pulled `pull` px past its rest spot until the neck
//             snaps (`breakAt`), then recoils to rest (gap right of the
//             island)
//   "hidden"  a status runs but the island is not the bar (module, Minimal,
//             ticker): absorbed into the island's end
//   "none"    no status: absorbed, then gone
// Position springs to TARGET island geometry (a target read from the
// animated island would restart the spring every frame); the neck is drawn
// from the ANIMATED island end, so it stretches while the island moves.
Item {
    id: root
    anchors.fill: parent

    required property var cfg
    required property color color
    required property string mode
    // Live (animated) island rect, window coords.
    required property real islandX
    required property real islandY
    required property real islandW
    required property real islandH
    required property real islandR
    // Target island geometry.
    required property real targetW
    required property real targetH
    required property real targetR
    // Bar height (drop size when cfg.size is 0).
    required property real barHeight
    // Island width spring (inline: the drop rides the island's end in step).
    property var widthSpring: null

    readonly property bool shown: root.mode === "out" || root.mode === "inline"
    // Painted at all: from the moment it is shown until it has merged back.
    // Not tied to `merged` alone — at shell start the window / island
    // geometry is still settling, the (invisible) drop springs across the
    // bar from near the left edge and was seen flying in from the corner.
    property bool live: false
    onShownChanged: if (root.shown) root.live = true
    onMergedChanged: if (root.merged && !root.shown) root.live = false
    readonly property real dropR: ((root.cfg?.size ?? 0) > 0 ? root.cfg.size : root.barHeight) / 2
    readonly property real gap: root.cfg?.gap ?? 8
    readonly property real pullPx: root.cfg?.pull ?? 12

    // Live end rounding of the island (circle 1).
    readonly property real r1: Math.max(0, Math.min(root.islandR, root.islandH / 2))
    readonly property real c1x: root.islandX + root.islandW - root.r1
    readonly property real c1y: root.islandY + root.islandH / 2
    // Target end rounding.
    readonly property real r1T: Math.max(0, Math.min(root.targetR, root.targetH / 2))
    readonly property real c1xT: root.width / 2 + root.targetW / 2 - root.r1T
    readonly property real restX: root.c1xT + root.r1T + root.gap + root.dropR

    // Split sequence: pulled further out until the neck snaps, then rest.
    property bool pulling: false
    property bool broken: false
    onModeChanged: {
        root.pulling = root.mode === "out" && root.dist < root.breakDist;
        root.broken = root.mode === "out" && !root.pulling;
    }
    Component.onCompleted: {
        // Starts where its bindings put it (no spring from 0); assigning
        // cx / r here would drop those bindings.
        root.broken = root.mode === "out";
        root.live = root.shown;
        xBehavior.enabled = true;
        rBehavior.enabled = true;
    }

    property real cx: root.mode === "out" ? root.restX + (root.pulling ? root.pullPx : 0) : root.c1xT
    Behavior on cx {
        id: xBehavior
        enabled: false
        Spring {
            stiffness: root.mode === "inline" ? (root.widthSpring?.stiffness ?? 4) : (root.cfg?.dropStiffness ?? 3)
            damp: root.mode === "inline" ? (root.widthSpring?.damping ?? 0.35) : (root.cfg?.dropDamping ?? 0.3)
            eps: 0.05
        }
    }
    readonly property real cy: root.c1y
    // Absorbed: never larger than the drop (a module's big end rounding
    // would inflate it into a bump), shrinks into a small end (Minimal).
    property real r: root.shown ? root.dropR : Math.min(root.dropR, root.r1T)
    Behavior on r {
        id: rBehavior
        enabled: false
        Spring { eps: 0.05 }
    }

    readonly property real dist: Math.abs(root.cx - root.c1x)
    readonly property real touch: root.r1 + root.r
    // Neck snaps here while splitting off (between rest and the pull).
    readonly property real breakDist: root.touch + (root.gap + root.pullPx) * (root.cfg?.breakAt ?? 0.7)
    // Re-joining: the neck reaches out from just inside the rest spot.
    readonly property real joinDist: root.touch + root.gap * 0.9
    // Ring while sucked back in: open at the rest spot, shut once the drop
    // is in to `closeAt` × the touching distance (centres) — ahead of the merge.
    readonly property real squeeze: root.shown ? 1
        : Metaball.smoothstep(root.touch * (root.cfg?.closeAt ?? 0.6), root.touch + root.gap, root.dist)
    onDistChanged: {
        if (root.pulling && root.dist >= root.breakDist) {
            root.pulling = false;
            root.broken = true;
        }
    }

    // Merged = sitting in the island's end (covered): nothing to paint
    // (the Minimal strip is translucent).
    readonly property bool merged: !root.shown && root.dist < 0.75 && Math.abs(root.r - Math.min(root.dropR, root.r1T)) < 0.75
    readonly property real neckFar: root.mode === "out" ? root.breakDist : root.joinDist
    readonly property real spread: root.broken ? 0
        : (root.cfg?.neckSpread ?? 0.5) * (1 - Metaball.smoothstep(root.touch, root.neckFar, root.dist))
    readonly property string neckPath: Metaball.neck([root.c1x, root.c1y], root.r1, [root.cx, root.cy], root.r,
        root.spread, root.cfg?.neckHandle ?? 2.4)

    // Opacity only (a CurveRenderer Shape toggled via `visible` never
    // repaints again).
    Shape {
        anchors.fill: parent
        opacity: root.live && !root.merged ? 1 : 0
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: root.color
            strokeColor: "transparent"
            strokeWidth: 0
            PathAngleArc {
                centerX: root.cx
                centerY: root.cy
                radiusX: root.r
                radiusY: root.r
                startAngle: 0
                sweepAngle: 360
            }
        }
        ShapePath {
            fillColor: root.color
            strokeColor: "transparent"
            strokeWidth: 0
            PathSvg { path: root.neckPath }
        }
    }
}
