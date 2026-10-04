import QtQuick
import "../components"

// Shared Element Transitions (spec): an element going from a background
// indicator into a module does NOT die — it is reparented into this layer
// (above all island content), flown to its slot in the module and reparented
// into that slot; closing the module flies it back home the same way.
// Independent of ContentSwap's blur->fade: the element is never blurred, the
// rest of the module fades in around it.
//
// Contract, declared ON the element's owner (e.g. indicators/Music.qml):
//   readonly property Item sharedElement: <the visual item that flies>
//   readonly property var sharedTransition: ({
//       target: "player",             // module name
//       slot: "cover",                // module.sharedSlot(slot) -> Item
//       properties: { radius: "slot" },  // animated props: number/color
//                                     // values, or "slot" = slot[prop]
//       duration: 300,                // timed curves only
//       curve: "spring"               // "spring" (default) or Easing.Type
//   })
//   readonly property var sharedTransitions // optional: { module: contract }
//                                     // when one element serves several
//                                     // modules (wins over sharedTransition)
//   function restoreShared()          // re-binds the element at home
//   readonly property Item sharedHome      // optional: exact home box
//                                     // (default: the owner itself)
//   readonly property var sharedHomeValues // optional: LIVE home values
//                                     // for the return flight (e.g. the
//                                     // current time, not the launch one)
// Property keys may be paths ("font.pixelSize"). Numbers and colours are
// interpolated; anything else (strings) switches at the halfway point.
// x/y/width/height always fly to the slot's live geometry (the slot moves
// with the island spring, so the target is re-read every frame).
// A slot is an Item with `property Item docked`: set while an element is
// headed to / sitting in it, so the module hides its own fallback.
Item {
    id: root
    anchors.fill: parent
    z: 999

    // (moduleName, slotKey) -> Item | null; provided by the island.
    property var slotResolver: null

    // Single flight (one shared element at a time).
    property Item el: null
    property Item owner: null           // element's home (contract holder)
    property var contract: null
    property Item slot: null
    readonly property string module: root.contract?.target ?? ""
    property string phase: ""           // "out" | "landed" | "home" | ""
    property real p: 0
    property var fromRect: null
    property var fromProps: ({})
    property var homeProps: ({})
    // Bottom edge of an element currently in the layer (0 otherwise): the
    // island keeps its window tall enough for it (Island.paintBottom).
    readonly property real flightBottom: (root.el && root.el.parent === root) ? root.el.y + root.el.height : 0

    function lerp(a: real, b: real, t: real): real {
        return a + (b - a) * t;
    }
    function isColor(v: var): bool {
        return v !== null && typeof v === "object" && v.r !== undefined && v.a !== undefined;
    }
    function mix(a: var, b: var, t: real): var {
        if (root.isColor(a) && root.isColor(b))
            return Qt.rgba(root.lerp(a.r, b.r, t), root.lerp(a.g, b.g, t), root.lerp(a.b, b.b, t), root.lerp(a.a, b.a, t));
        if (typeof a === "number" && typeof b === "number")
            return root.lerp(a, b, t);
        return t < 0.5 ? a : b;
    }
    // Dotted property paths ("font.pixelSize"). Two-level writes go through
    // the full expression so the value-type (font) writes back.
    function getPath(obj: var, key: string): var {
        return key.split(".").reduce((o, k) => (o === null || o === undefined) ? undefined : o[k], obj);
    }
    function setPath(obj: var, key: string, v: var): void {
        const parts = key.split(".");
        if (parts.length === 1)
            obj[key] = v;
        else if (parts.length === 2)
            obj[parts[0]][parts[1]] = v;
    }
    // Detached copy: reading a colour/font property yields a live value-type
    // REFERENCE — kept as a start value it would follow every write and
    // skew the interpolation.
    function snapshot(v: var): var {
        return root.isColor(v) ? Qt.rgba(v.r, v.g, v.b, v.a) : v;
    }
    function homeItem(): Item {
        return root.owner?.sharedHome ?? root.owner;
    }
    function homeValue(key: string): var {
        const live = root.owner?.sharedHomeValues;
        return (live && live[key] !== undefined) ? live[key] : root.homeProps[key];
    }
    function rectOf(item: Item): var {
        const pt = item.mapToItem(root, 0, 0);
        return { x: pt.x, y: pt.y, w: item.width, h: item.height };
    }
    function propTarget(key: string): var {
        const v = root.contract.properties[key];
        return v === "slot" ? root.getPath(root.slot, key) : v;
    }

    // Lift the element off its current parent into the layer, keeping its
    // on-screen geometry.
    function lift(): void {
        root.fromRect = root.rectOf(root.el);
        root.el.anchors.fill = undefined;
        root.el.anchors.centerIn = undefined;
        root.el.parent = root;
        root.el.x = root.fromRect.x;
        root.el.y = root.fromRect.y;
        root.el.width = root.fromRect.w;
        root.el.height = root.fromRect.h;
        const props = {};
        for (const k in (root.contract.properties ?? {}))
            props[k] = root.snapshot(root.getPath(root.el, k));
        root.fromProps = props;
    }

    function startAnim(): void {
        root.p = 0;
        const curve = root.contract.curve ?? "spring";
        if (curve === "spring") {
            springAnim.restart();
        } else {
            timedAnim.duration = root.contract.duration ?? 300;
            timedAnim.easing.type = curve;
            timedAnim.restart();
        }
    }

    // Contract `owner` offers for module `name` (null = none).
    function contractFor(owner: var, name: string): var {
        const many = owner?.sharedTransitions?.[name];
        if (many)
            return many;
        const one = owner?.sharedTransition;
        return one?.target === name ? one : null;
    }

    // Bar -> module. `owner` carries the contract and the element.
    function launch(owner: Item, name: string): void {
        const c = root.contractFor(owner, name);
        const element = owner?.sharedElement;
        if (!c || !element)
            return;
        // Same element still flying home (e.g. the next queued notification
        // reopens the module during the collapse gap): turn around from
        // where it is instead of snapping home and lifting again.
        if (root.el === element && root.phase === "home") {
            springAnim.stop();
            timedAnim.stop();
            root.contract = c;
            root.slot = null;
            root.lift();
            root.phase = "out";
            return;
        }
        if (root.el)
            root.abort();
        root.owner = owner;
        root.contract = c;
        root.el = element;
        root.slot = null;
        root.homeProps = {};
        for (const k in (c.properties ?? {}))
            root.homeProps[k] = root.snapshot(root.getPath(element, k));
        root.lift();
        root.phase = "out";
        // Animation starts once the slot exists (the module is created at
        // the ContentSwap handover, a few frames after the request).
    }

    // Module -> home (module closing or replaced).
    function returnHome(): void {
        if (!root.el || root.phase === "home" || root.phase === "")
            return;
        springAnim.stop();
        timedAnim.stop();
        if (root.slot && root.slot.docked === root.el)
            root.slot.docked = null;
        if (!root.owner || (root.homeItem()?.width ?? 0) < 1) {
            // Home is gone/collapsed (indicator unloaded): nothing to fly to.
            root.abort();
            return;
        }
        root.lift();
        root.phase = "home";
        root.startAnim();
    }

    // Drop the flight, re-docking the element home without animation.
    function abort(): void {
        springAnim.stop();
        timedAnim.stop();
        if (root.slot && root.slot.docked === root.el)
            root.slot.docked = null;
        if (root.el && root.owner)
            root.dockHome();
        root.reset();
    }

    function dockHome(): void {
        root.el.parent = root.owner;
        for (const k in root.homeProps)
            root.setPath(root.el, k, root.homeValue(k));
        root.owner.restoreShared?.();
    }

    function reset(): void {
        root.phase = "";
        root.el = null;
        root.owner = null;
        root.contract = null;
        root.slot = null;
    }

    function step(): void {
        if (!root.el) {
            root.reset();
            return;
        }
        let to = null;
        let targetProps = {};
        if (root.phase === "out") {
            if (!root.slot) {
                root.slot = root.slotResolver?.(root.module, root.contract.slot ?? "") ?? null;
                if (!root.slot)
                    return; // module not created yet: hold position
                root.slot.docked = root.el; // module hides its own fallback
                root.startAnim();
            }
            to = root.rectOf(root.slot);
            for (const k in root.fromProps)
                targetProps[k] = root.propTarget(k);
        } else if (root.phase === "home") {
            if (!root.owner) {
                root.abort();
                return;
            }
            to = root.rectOf(root.homeItem());
            for (const k in root.fromProps)
                targetProps[k] = root.homeValue(k);
        } else {
            return;
        }
        const t = root.p;
        root.el.x = root.lerp(root.fromRect.x, to.x, t);
        root.el.y = root.lerp(root.fromRect.y, to.y, t);
        root.el.width = Math.max(0, root.lerp(root.fromRect.w, to.w, t));
        root.el.height = Math.max(0, root.lerp(root.fromRect.h, to.h, t));
        for (const k in root.fromProps)
            if (targetProps[k] !== undefined)
                root.setPath(root.el, k, root.mix(root.fromProps[k], targetProps[k], t));
    }

    function finish(): void {
        root.p = 1;
        root.step();
        if (root.phase === "out" && root.slot) {
            root.el.parent = root.slot;
            root.el.x = 0;
            root.el.y = 0;
            root.el.anchors.fill = root.slot;
            root.phase = "landed";
        } else if (root.phase === "home") {
            root.dockHome();
            root.reset();
        }
    }

    // Per-frame tracking: the target (slot / home) moves with the island.
    FrameAnimation {
        running: root.phase === "out" || root.phase === "home"
        onTriggered: root.step()
    }

    // Default curve: the island's spring (movement = springs, spec).
    Spring {
        id: springAnim
        target: root
        property: "p"
        to: 1
        eps: 0.002
        onFinished: root.finish()
    }
    NumberAnimation {
        id: timedAnim
        target: root
        property: "p"
        to: 1
        onFinished: root.finish()
    }
}
