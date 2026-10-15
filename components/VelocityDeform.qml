import QtQuick
import "../config"

// Liquid stretch while an item moves (port of pShell's BlobRect deform):
// each frame the item's CENTRE velocity sets a target deform — stretch
// 1 + m along the motion, 1 / (1 + m) across it (area-preserving),
// m = min(speed · scale, maxStretch) · size attenuation (· diagonal damping,
// deform.diagonal: 1 = full stretch at any angle, lower = barely any along
// a diagonal and no skew) — and the 2×2 matrix
// chases it on an under-damped spring, so a stop wobbles back to identity.
// Usage: `transform: VelocityDeform { item: <the transformed item> }`.
// Frames run only while the item moves or the spring is still settling.
Matrix4x4 {
    id: root

    property Item item: null
    // Stable TARGET size for the attenuation (a growing item would otherwise
    // deform at full strength while small); defaults to the live size.
    property real sizeW: root.item?.width ?? 0
    property real sizeH: root.item?.height ?? 0
    property bool active: root.item?.visible ?? false
    // Optional velocity source instead of the item's on-screen centre: a
    // position in ANY fixed frame (the launcher plate's slot in list
    // content coords — on screen it stands still while the list scrolls
    // under a held key, yet it is travelling through the list).
    property bool useSource: false
    property real sourceX: 0
    property real sourceY: 0
    onSourceXChanged: if (root.useSource) root.wake()
    onSourceYChanged: if (root.useSource) root.wake()

    readonly property var cfg: Config.data.deform
    readonly property real atten: {
        const full = root.cfg.sizeFull;
        const over = Math.max(0, Math.max(root.sizeW, root.sizeH) - full);
        return Math.max(root.cfg.sizeFloor, full / (full + over * root.cfg.sizeStrength));
    }

    property real m00: 1
    property real m01: 0
    property real m11: 1
    property real v00: 0
    property real v01: 0
    property real v11: 0
    property bool hasPrev: false
    property real prevX: 0
    property real prevY: 0

    // Centred: p' = c + M (p − c), c = the item's own centre.
    readonly property real cx: (root.item?.width ?? 0) / 2
    readonly property real cy: (root.item?.height ?? 0) / 2
    matrix: Qt.matrix4x4(root.m00, root.m01, 0, root.cx - root.m00 * root.cx - root.m01 * root.cy,
        root.m01, root.m11, 0, root.cy - root.m01 * root.cx - root.m11 * root.cy,
        0, 0, 1, 0,
        0, 0, 0, 1)

    function centre(): point {
        if (root.useSource)
            return Qt.point(root.sourceX, root.sourceY);
        const it = root.item;
        return it.parent.mapToItem(null, it.x + it.width / 2, it.y + it.height / 2);
    }

    function wake(): void {
        if (root.active && root.cfg.scale > 0 && !driver.running) {
            root.hasPrev = false;
            driver.running = true;
        }
    }

    function rest(): void {
        driver.running = false;
        root.hasPrev = false;
        root.m00 = root.m11 = 1;
        root.m01 = root.v00 = root.v01 = root.v11 = 0;
    }

    function step(dt: real): void {
        const p = root.centre();
        if (!root.hasPrev || dt > 0.1 || dt < 0.001) {
            root.prevX = p.x;
            root.prevY = p.y;
            root.hasPrev = true;
            return;
        }
        const vx = (p.x - root.prevX) / dt, vy = (p.y - root.prevY) / dt;
        root.prevX = p.x;
        root.prevY = p.y;
        const speed = Math.hypot(vx, vy);

        let t00 = 1, t01 = 0, t11 = 1;
        if (speed > 5) {
            const ca = vx / speed, sa = vy / speed;
            // Diagonal damping (deform.diagonal, 1 = plain rotated stretch):
            // the stretch fades toward 45° (|sin 2θ| = 1) and its skew
            // (off-diagonal term) is scaled down — axis motion unchanged.
            const dg = root.cfg.diagonal ?? 1;
            const k = 1 - Math.abs(2 * ca * sa) * (1 - dg);
            const s = 1 + Math.min(speed * root.cfg.scale, root.cfg.maxStretch) * root.atten * k;
            const c = 1 / s;
            t00 = s * ca * ca + c * sa * sa;
            t01 = (s - c) * ca * sa * dg;
            t11 = s * sa * sa + c * ca * ca;
        }

        // Explicit Euler is unstable on a stiff spring at long frames:
        // fixed ≤ 1/240 s sub-steps (as in pShell).
        const k = root.cfg.stiffness, d = root.cfg.damping;
        const n = Math.min(64, Math.max(1, Math.ceil(dt * 240)));
        const h = dt / n;
        let m00 = root.m00, m01 = root.m01, m11 = root.m11;
        let v00 = root.v00, v01 = root.v01, v11 = root.v11;
        for (let i = 0; i < n; ++i) {
            v00 += (-k * (m00 - t00) - d * v00) * h;
            m00 += v00 * h;
            v01 += (-k * (m01 - t01) - d * v01) * h;
            m01 += v01 * h;
            v11 += (-k * (m11 - t11) - d * v11) * h;
            m11 += v11 * h;
        }
        root.v00 = v00;
        root.v01 = v01;
        root.v11 = v11;
        root.m00 = m00;
        root.m01 = m01;
        root.m11 = m11;

        if (speed < 5 && Math.abs(m00 - 1) + Math.abs(m01) + Math.abs(m11 - 1) < 0.004
                && Math.abs(v00) + Math.abs(v01) + Math.abs(v11) < 0.05)
            root.rest();
    }

    onActiveChanged: if (!root.active) root.rest()

    property FrameAnimation driver: FrameAnimation {
        onTriggered: root.step(frameTime)
    }

    property Connections watcher: Connections {
        target: root.item
        function onXChanged() { if (!root.useSource) root.wake(); }
        function onYChanged() { if (!root.useSource) root.wake(); }
    }
}
