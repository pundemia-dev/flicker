import QtQuick
import "../../../components"

// Fill slider (volume, brightness), iOS style: the card itself is the
// track, a light fill grows from the bottom (small/tall/large) or the left
// (wide/panorama). Drags are RELATIVE (iOS): the value moves by the
// pointer delta, a press never jumps it. Tap = `activate()` (mute), long
// press = edit mode, wheel = ±cfg.wheelStep. Layout per form:
//   small     glyph centred
//   tall      glyph at the bottom
//   wide      glyph left; percent right once there is room (>= 4 units)
//   large /   glyph + title top-left, percent bottom-left
//   panorama
Item {
    id: root
    property var card: null
    property string glyph: ""
    property string title: ""
    // Normalised 0..1.
    property real value: 0
    property var activate: null
    signal moved(real value)

    readonly property var theme: root.card?.theme ?? null
    readonly property var cfg: root.card?.cfg ?? null
    readonly property string form: root.card?.form ?? "small"
    readonly property bool horizontal: root.form === "wide" || root.form === "panorama"
    readonly property real pad: (root.cfg?.padding) ?? 12
    readonly property real unit: (root.cfg?.unit) ?? 72

    // Local value while dragging (the service applies volume async).
    property real dragValue: 0
    readonly property real shown: area.dragging ? root.dragValue : Math.max(0, Math.min(1, root.value))
    property real fill: root.shown
    Behavior on fill {
        enabled: !area.dragging
        Spring { stiffness: 5; damp: 0.5; eps: 0.002 }
    }

    function set(v: real): void {
        root.dragValue = Math.max(0, Math.min(1, v));
        root.moved(root.dragValue);
    }

    RoundedClip {
        anchors.fill: parent
        radius: root.card?.radius ?? 36

        Rectangle {
            color: root.theme?.qsFill ?? "#F2F2F7"
            width: root.horizontal ? root.width * root.fill : root.width
            height: root.horizontal ? root.height : root.height * root.fill
            y: root.horizontal ? 0 : root.height - height
        }
    }

    // Glyph slot: centre (small), bottom (tall), left (wide), top-left (large).
    readonly property point glyphCenter: {
        const half = root.unit / 2;
        if (root.form === "small")
            return Qt.point(root.width / 2, root.height / 2);
        if (root.form === "tall")
            return Qt.point(root.width / 2, root.height - half);
        if (root.horizontal && root.card?.spanH === 1)
            return Qt.point(half, root.height / 2);
        return Qt.point(root.pad + 14, root.pad + 14);
    }
    // Dark glyph/labels once the light fill covers them.
    function covered(px: real, py: real): bool {
        return root.horizontal ? px < root.width * root.fill : py > root.height * (1 - root.fill);
    }

    Icon {
        x: root.glyphCenter.x - width / 2
        y: root.glyphCenter.y - height / 2
        text: root.glyph
        font.family: root.theme?.iconFamily ?? "tabler-icons"
        iconSize: (root.cfg?.iconSize) ?? 22
        iconColor: root.covered(root.glyphCenter.x, root.glyphCenter.y) ? (root.theme?.qsOnFill ?? "#1C1C1E") : "white"
    }
    Text {
        id: titleLabel
        visible: root.form === "large" || root.form === "panorama"
        x: root.pad + 34
        y: root.glyphCenter.y - height / 2
        width: root.width - x - root.pad
        text: root.title
        font.pixelSize: (root.cfg?.titleSize) ?? 13
        font.weight: Font.DemiBold
        elide: Text.ElideRight
        color: root.covered(x, y + height / 2) ? (root.theme?.qsOnFill ?? "#1C1C1E") : "white"
    }
    Text {
        id: pct
        visible: root.form === "large" || root.form === "panorama" || (root.form === "wide" && (root.card?.spanW ?? 1) >= 4)
        x: root.form === "wide" ? root.width - width - root.unit / 2 + 8 : root.pad
        y: root.form === "wide" ? (root.height - height) / 2 : root.height - height - root.pad
        text: `${Math.round(root.shown * 100)}%`
        font.pixelSize: (root.cfg?.titleSize) ?? 13
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
        color: root.covered(x + width / 2, y + height / 2) ? (root.theme?.qsOnFill ?? "#1C1C1E") : "white"
    }

    MouseArea {
        id: area
        anchors.fill: parent
        pressAndHoldInterval: (root.cfg?.holdMs) ?? 450
        property point start
        property real startValue: 0
        property bool dragging: false
        property bool held: false

        onPressed: mouse => {
            start = Qt.point(mouse.x, mouse.y);
            startValue = root.shown;
            dragging = false;
            held = false;
        }
        onPressAndHold: {
            if (dragging)
                return;
            held = true;
            root.card?.holdRequested();
        }
        onPositionChanged: mouse => {
            if (held)
                return;
            const d = root.horizontal ? (mouse.x - start.x) / root.width : (start.y - mouse.y) / root.height;
            if (!dragging && Math.abs(d) * (root.horizontal ? root.width : root.height) > 3) {
                root.dragValue = startValue;
                dragging = true;
            }
            if (dragging)
                root.set(startValue + d);
        }
        onReleased: {
            if (!dragging && !held && typeof root.activate === "function")
                root.activate();
            dragging = false;
        }
        onCanceled: dragging = false
        onWheel: wheel => {
            const step = (root.cfg?.wheelStep) ?? 0.05;
            root.set(root.shown + (wheel.angleDelta.y > 0 ? step : -step));
        }
    }
}
