import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import "../config"

// Drop expansion (user design, first built for the QS Wi‑Fi card): a source
// item (button, card) turns into a panel through ONE shape that morphs in
// three spring phases, each starting when the previous reaches `handoff`:
//   drop  source rect -> a circle (diameter = short side x dropScale) on the
//         source centre; the source's look blur-fades out inside it
//   fly   the drop travels to the panel centre (VelocityDeform stretch)
//   grow  drop -> panel rect; the panel content blur-fades in
// close() runs it backwards (the source look returns while the drop flies
// home). Panel centre = source centre moved just enough for the panel to
// fit inside `bounds` minus `margin` — per axis a clamp, the shortest move.
//
// Usage: put one DropExpand over the area the panel may cover (it draws in
// its own coords; anchors.fill the module / view) and call
//   open(source, { panel: Component, width, height,
//                  radius,        // panel radius (default panelRadius)
//                  sourceRadius,  // default source.radius ?? 0
//                  layer,         // item drawn as the source's look (hideSource
//                                 // texture; default = source itself)
//                  color,         // starting fill: color or function () -> color
//                                 // (live; default panelColor)
//                  payload })     // handed to the panel item
// The panel item gets `expander` (this) and `payload` if it declares them;
// close(fn) runs fn after the drop has landed (actions from a menu).
// Click / hold triggers: components/DropExpandArea.qml. Taps outside the
// panel close it (`closeOnOutside`). The live shape (curCx/curCy/curW/curH/
// curR + deformMatrix) is public so hosts can cut things out under it.
Item {
    id: root

    // Area (own coords) the panel must fit in, inset by `margin`.
    property rect bounds: Qt.rect(0, 0, root.width, root.height)
    property real margin: 0
    property color panelColor: "#1C1C1E"
    // Inner shadow along the shape's rim (components/InnerShadow); 0 = none.
    property int shadowSize: 0
    property real shadowStrength: 0
    property real panelRadius: 16
    // Clip the panel content to the shape's rounded rect (ClippingRectangle),
    // so scrolled lists don't poke out of the corners.
    property bool clipPanel: false
    property bool closeOnOutside: true
    // Blur-behind (null = off): an item drawn behind this one, at
    // backdropPos (own coords); the shape shows it blurred by backdropBlur px.
    // The host hides the sharp original under the shape itself.
    property Item backdrop: null
    property point backdropPos: Qt.point(0, 0)
    property int backdropBlur: 48
    property real backdropInset: 1.5

    // Motion (Config.dropExpand defaults; set per instance to override).
    readonly property var cfg: Config.data.dropExpand ?? ({})
    property real dropScale: root.cfg.dropScale ?? 0.9
    property real handoff: root.cfg.handoff ?? 0.5
    property real dropStiffness: root.cfg.dropStiffness ?? 14
    property real dropDamping: root.cfg.dropDamping ?? 0.5
    property real flyStiffness: root.cfg.flyStiffness ?? 12
    property real flyDamping: root.cfg.flyDamping ?? 0.45
    property real growStiffness: root.cfg.growStiffness ?? 12
    property real growDamping: root.cfg.growDamping ?? 0.45
    property real fadeStiffness: root.cfg.fadeStiffness ?? 12

    // The source left its slot (hide its surface) / came back.
    signal lifted(Item source)
    signal landed(Item source)

    property Item source: null
    property bool opened: false
    readonly property bool active: root.source !== null
    readonly property Item panel: panelLoader.item
    readonly property matrix4x4 deformMatrix: deform.matrix

    property var opts: ({})
    property Item layerItem: null

    // Snapshot taken at open (own coords).
    property real fromX: 0
    property real fromY: 0
    property real fromW: 1
    property real fromH: 1
    property real fromR: 0
    property real toCx: 0
    property real toCy: 0
    property real panelW: 1
    property real panelH: 1
    property real panelR: 0
    readonly property real dropD: Math.min(root.fromW, root.fromH) * root.dropScale

    // Phase targets; the springs chase them.
    property bool dropOn: false
    property bool flyOn: false
    property bool growOn: false
    property real dropP: root.dropOn ? 1 : 0
    property real flyP: root.flyOn ? 1 : 0
    property real growP: root.growOn ? 1 : 0
    Behavior on dropP { Spring { stiffness: root.dropStiffness; damp: root.dropDamping; eps: 0.002 } }
    Behavior on flyP { Spring { stiffness: root.flyStiffness; damp: root.flyDamping; eps: 0.002 } }
    Behavior on growP { Spring { stiffness: root.growStiffness; damp: root.growDamping; eps: 0.002 } }
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

    readonly property color fromColor: {
        const c = root.opts.color;
        return typeof c === "function" ? c() : (c ?? root.panelColor);
    }
    readonly property color fill: root.mix(root.fromColor, root.panelColor, root.growP)

    function open(src: Item, options: var): bool {
        if (root.active) {
            // Re-open while it is still folding back.
            if (src === root.source && !root.opened) {
                root.opened = true;
                root.advance();
                return true;
            }
            return false;
        }
        const o = options ?? {};
        if (!src || !o.panel)
            return false;
        const p = src.mapToItem(root, 0, 0);
        const b = root.bounds, m = root.margin;
        root.opts = o;
        root.fromX = p.x;
        root.fromY = p.y;
        root.fromW = src.width;
        root.fromH = src.height;
        root.fromR = o.sourceRadius ?? src.radius ?? 0;
        root.panelW = Math.min(o.width ?? b.width, b.width - 2 * m);
        root.panelH = Math.min(o.height ?? b.height, b.height - 2 * m);
        root.panelR = o.radius ?? root.panelRadius;
        root.toCx = root.clamp(p.x + src.width / 2, b.x + m + root.panelW / 2, b.x + b.width - m - root.panelW / 2);
        root.toCy = root.clamp(p.y + src.height / 2, b.y + m + root.panelH / 2, b.y + b.height - m - root.panelH / 2);
        root.layerItem = o.layer ?? src;
        root.source = src;
        panelLoader.sourceComponent = o.panel;
        root.lifted(src);
        root.opened = true;
        root.dropOn = true;
        return true;
    }

    // `after` runs once the drop has landed back on the source (an action
    // that removes the source must not tear it out from under the flight).
    property var afterClose: null
    function close(after: var): void {
        if (typeof after === "function")
            root.afterClose = after;
        if (!root.active || !root.opened)
            return;
        root.opened = false;
        root.advance();
    }

    function toggle(src: Item, options: var): void {
        if (root.opened && src === root.source)
            root.close();
        else
            root.open(src, options);
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
        const src = root.source;
        panelLoader.sourceComponent = null;
        root.layerItem = null;
        root.source = null;
        root.opts = ({});
        root.landed(src);
        const after = root.afterClose;
        root.afterClose = null;
        if (after)
            after();
    }

    // Outside the panel: tap folds it back; eats everything else meanwhile.
    MouseArea {
        anchors.fill: parent
        enabled: root.active && root.closeOnOutside
        hoverEnabled: enabled
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

        // Blur-behind: the backdrop item, blurred, under the fill — the
        // shape frosts what it covers instead of showing a hole. Masked to
        // the shape inset by backdropInset (the mask edge is binary; the
        // fill's antialiased rim covers the steps).
        Item {
            id: behind
            anchors.fill: parent
            visible: root.backdrop !== null
            layer.enabled: behind.visible
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: behindMask
                autoPaddingEnabled: false
            }
            MultiEffect {
                x: root.backdropPos.x - shape.x
                y: root.backdropPos.y - shape.y
                width: root.backdrop?.width ?? 0
                height: root.backdrop?.height ?? 0
                source: behindSrc
                blurEnabled: true
                blur: 1
                blurMax: root.backdropBlur
                autoPaddingEnabled: false
            }
            ShaderEffectSource {
                id: behindSrc
                visible: false
                sourceItem: behind.visible ? root.backdrop : null
                live: true
            }
        }
        Item {
            id: behindMask
            anchors.fill: parent
            visible: false
            layer.enabled: behind.visible
            Rectangle {
                anchors.fill: parent
                anchors.margins: root.backdropInset
                radius: Math.max(0, root.curR - root.backdropInset)
                color: "white"
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: root.curR
            color: root.fill
        }
        InnerShadow {
            anchors.fill: parent
            visible: root.shadowSize > 0 && root.shadowStrength > 0
            radius: root.curR
            size: root.shadowSize
            strength: root.shadowStrength
        }
        // Presses on the panel body stay here.
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onWheel: wheel => wheel.accepted = true
        }

        // Source look: fixed source-size layer, scaled to fit the shape.
        FadeBlur {
            width: root.fromW
            height: root.fromH
            anchors.centerIn: parent
            scale: Math.min(shape.width / root.fromW, shape.height / root.fromH)
            stiffness: root.fadeStiffness
            shown: !root.opened && root.growP < 0.5
            ShaderEffectSource {
                anchors.fill: parent
                sourceItem: root.layerItem
                hideSource: root.active
                live: true
            }
        }

        // Panel: laid out at its final size, scaled up with the shape.
        FadeBlur {
            id: panelFade
            width: root.panelW
            height: root.panelH
            anchors.centerIn: parent
            scale: Math.min(shape.width / root.panelW, shape.height / root.panelH)
            stiffness: root.fadeStiffness
            shown: root.opened && root.growOn
            // Radius in panel coords: the shape's, undone by the scale.
            ClippingRectangle {
                anchors.fill: parent
                color: "transparent"
                radius: root.clipPanel && panelFade.scale > 0 ? Math.min(root.curR / panelFade.scale, width / 2, height / 2) : 0
                Loader {
                    id: panelLoader
                    anchors.fill: parent
                    onLoaded: {
                        if ("expander" in item)
                            item.expander = root;
                        if ("payload" in item)
                            item.payload = root.opts.payload ?? null;
                    }
                }
            }
        }
    }
}
