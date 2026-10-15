import QtQuick
import "../../components"

// Expanded card (long press on a card that has a panel, QsCardFactory
// .panelFor): one shape on top of the whole module morphs in three spring
// phases, each starting when the previous one reaches `expand.handoff`:
//   drop  card rect -> a circle (diameter = short side x dropScale) on the
//         card centre; the card content blur-fades out inside it
//   fly   the drop's centre travels over the grid to the panel centre
//         (VelocityDeform stretches it along the flight)
//   grow  drop -> panel rect; the panel blur-fades in
// Closing (tap outside the panel, close()) runs the same phases backwards
// and the card content fades back in while the drop flies home.
//
// Panel centre = the card centre moved just enough for the panel (free px
// size, `expand.panels.<id>`, not grid cells) to fit inside the grid area
// (island margins, never over the rail column): per axis a clamp, which is
// the shortest move that fits. The island clears its frost tint under the
// shape (module `knockoutClear`), the module cuts the grid out there.
//
// The card stays in its slot with `expandedOut` (no surface); its content
// is drawn here as a hideSource texture, so the drop starts pixel-identical.
Item {
    id: root
    required property var cfg
    required property var theme
    property var frost: null
    property var services: null
    property var cardFactory: null
    // Area the panel must fit in (+ margins): the grid, not the rail.
    property real boundsW: root.width
    property real boundsH: root.height

    readonly property var e: root.cfg.expand ?? ({})
    readonly property real handoff: root.e.handoff ?? 0.7

    property string cardId: ""
    property Item card: null
    property bool opened: false
    readonly property bool active: root.cardId !== ""
    readonly property Item panel: panelLoader.item
    readonly property bool wantsKeyboard: root.panel?.wantsKeyboard ?? false

    // Flight stretch of the shape (the module's cut-out follows it).
    readonly property matrix4x4 deformMatrix: deform.matrix
    readonly property real fadeStiffness: root.e.fadeStiffness ?? 8

    // Snapshot taken at open (module coords).
    property real fromX: 0
    property real fromY: 0
    property real fromW: 1
    property real fromH: 1
    property real fromR: 0
    property real toCx: 0
    property real toCy: 0
    property real panelW: 1
    property real panelH: 1
    readonly property real panelR: (root.e.panelRadius ?? 0) > 0 ? root.e.panelRadius : root.cfg.unit / 2
    readonly property real dropD: Math.min(root.fromW, root.fromH) * (root.e.dropScale ?? 0.9)

    // Phase targets; the springs below chase them.
    property bool dropOn: false
    property bool flyOn: false
    property bool growOn: false
    property real dropP: root.dropOn ? 1 : 0
    property real flyP: root.flyOn ? 1 : 0
    property real growP: root.growOn ? 1 : 0
    Behavior on dropP { Spring { stiffness: root.e.dropStiffness ?? 6; damp: root.e.dropDamping ?? 0.45; eps: 0.002 } }
    Behavior on flyP { Spring { stiffness: root.e.flyStiffness ?? 4; damp: root.e.flyDamping ?? 0.4; eps: 0.002 } }
    Behavior on growP { Spring { stiffness: root.e.growStiffness ?? 4; damp: root.e.growDamping ?? 0.42; eps: 0.002 } }
    onDropPChanged: root.advance()
    onFlyPChanged: root.advance()
    onGrowPChanged: root.advance()

    function lerp(a: real, b: real, t: real): real {
        return a + (b - a) * t;
    }
    function clamp(v: real, lo: real, hi: real): real {
        return lo > hi ? (lo + hi) / 2 : Math.max(lo, Math.min(hi, v));
    }
    function mix(a: color, b: color, t: real): color {
        const k = Math.max(0, Math.min(1, t));
        return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, a.a + (b.a - a.a) * k);
    }

    readonly property real curCx: root.lerp(root.fromX + root.fromW / 2, root.toCx, root.flyP)
    readonly property real curCy: root.lerp(root.fromY + root.fromH / 2, root.toCy, root.flyP)
    readonly property real curW: Math.max(1, root.lerp(root.lerp(root.fromW, root.dropD, root.dropP), root.panelW, root.growP))
    readonly property real curH: Math.max(1, root.lerp(root.lerp(root.fromH, root.dropD, root.dropP), root.panelH, root.growP))
    readonly property real curR: Math.max(0, Math.min(root.lerp(root.lerp(root.fromR, root.dropD / 2, root.dropP), root.panelR, root.growP), root.curW / 2, root.curH / 2))

    // Fill: the card's look (accent when on) -> the panel surface.
    readonly property color surfaceColor: root.frost?.surface(root.theme?.qsCardBg ?? "#000000") ?? (root.theme?.qsCardBg ?? "#000000")
    readonly property color panelColor: root.mix(root.theme?.qsCardBg ?? "#000000", root.theme?.qsPanelBg ?? "#8C141416", root.frost?.progress ?? 0)
    readonly property color cardColor: {
        const it = root.card?.contentLayer?.item ?? null;
        if (it && typeof it.onP === "number" && it.accent !== undefined)
            return root.mix(root.surfaceColor, it.accent, it.onP);
        return root.surfaceColor;
    }
    readonly property color fill: root.mix(root.cardColor, root.panelColor, root.growP)

    function open(c: Item): bool {
        if (root.active) {
            // Re-open while it is still folding back.
            if (c === root.card && !root.opened) {
                root.opened = true;
                root.advance();
                return true;
            }
            return false;
        }
        const comp = root.cardFactory?.panelFor(c.cardId) ?? null;
        if (!comp)
            return false;
        const p = c.mapToItem(root, 0, 0);
        const m = root.cfg.margins;
        const spec = root.e.panels?.[c.cardId] ?? {};
        root.fromX = p.x;
        root.fromY = p.y;
        root.fromW = c.width;
        root.fromH = c.height;
        root.fromR = c.radius;
        root.panelW = Math.min(spec.width ?? root.boundsW, root.boundsW - 2 * m);
        root.panelH = Math.min(spec.height ?? root.boundsH, root.boundsH - 2 * m);
        root.toCx = root.clamp(p.x + c.width / 2, m + root.panelW / 2, root.boundsW - m - root.panelW / 2);
        root.toCy = root.clamp(p.y + c.height / 2, m + root.panelH / 2, root.boundsH - m - root.panelH / 2);
        root.card = c;
        root.cardId = c.cardId;
        c.expandedOut = true;
        panelLoader.sourceComponent = comp;
        root.opened = true;
        root.dropOn = true;
        return true;
    }

    function close(): void {
        if (!root.active || !root.opened)
            return;
        root.opened = false;
        root.advance();
    }

    function advance(): void {
        if (!root.active)
            return;
        if (root.opened) {
            if (root.dropP >= root.handoff)
                root.flyOn = true;
            if (root.flyOn && root.flyP >= root.handoff)
                root.growOn = true;
            return;
        }
        root.growOn = false;
        if (root.growP <= 1 - root.handoff)
            root.flyOn = false;
        if (!root.flyOn && root.flyP <= 1 - root.handoff)
            root.dropOn = false;
        if (!root.dropOn && root.dropP < 0.02 && root.flyP < 0.02 && root.growP < 0.02)
            Qt.callLater(root.finish);
    }

    function finish(): void {
        if (root.opened || !root.active)
            return;
        if (root.card)
            root.card.expandedOut = false;
        panelLoader.sourceComponent = null;
        root.cardId = "";
        root.card = null;
    }

    // Outside the panel: tap folds it back; eats everything else.
    MouseArea {
        anchors.fill: parent
        enabled: root.active
        onClicked: root.close()
        onWheel: wheel => wheel.accepted = true
    }

    Item {
        id: shape
        x: root.curCx - width / 2
        y: root.curCy - height / 2
        width: root.curW
        height: root.curH
        visible: root.active
        transform: VelocityDeform {
            id: deform
            item: shape
            sizeW: root.dropD
            sizeH: root.dropD
        }

        Rectangle {
            anchors.fill: parent
            radius: root.curR
            color: root.fill
        }
        // Presses on the panel body stay here.
        MouseArea {
            anchors.fill: parent
            onWheel: wheel => wheel.accepted = true
        }

        // Card content: fixed card-size layer, scaled to fit the shape.
        FadeBlur {
            width: root.fromW
            height: root.fromH
            anchors.centerIn: parent
            scale: Math.min(shape.width / root.fromW, shape.height / root.fromH)
            stiffness: root.fadeStiffness
            shown: !root.opened && root.growP < 0.5
            ShaderEffectSource {
                anchors.fill: parent
                sourceItem: root.active ? (root.card?.contentLayer ?? null) : null
                hideSource: root.active
                live: true
            }
        }

        // Panel: laid out at its final size, scaled up with the shape.
        FadeBlur {
            width: root.panelW
            height: root.panelH
            anchors.centerIn: parent
            scale: Math.min(shape.width / root.panelW, shape.height / root.panelH)
            stiffness: root.fadeStiffness
            shown: root.opened && root.growOn
            Loader {
                id: panelLoader
                anchors.fill: parent
                onLoaded: {
                    item.services = root.services;
                    item.cfg = root.cfg;
                    item.theme = root.theme;
                    item.frost = root.frost;
                    item.expander = root;
                }
            }
        }
    }
}
