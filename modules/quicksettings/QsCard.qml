import QtQuick
import QtQuick.Shapes
import "../../components"

// One Quick Settings card shell: rounded surface (radius = unit/2, so 1x1
// is a circle and 1xN a pill), the content Loader and all card input.
// Geometry comes from the module; this file only reports gestures.
//
// Normal mode: tap → `tapped`, long press → `holdRequested` (edit mode),
// drag up → `closeRequested` (the card grabs presses, so it forwards the
// module's swipe-up close itself — GestureZones below never sees them).
// Content controls (sliders, media buttons) sit above and take their own
// presses. Edit mode: content is disabled, the body drags the card
// (move*), the bottom-right arc resizes it (resize*), the "−" badge
// removes it.
//
// `form` is what card content lays itself out by (iOS: every control has
// its own layout per shape): small 1x1, wide Nx1, tall 1xN, large NxN,
// panorama = wider than tall with >= 2 rows.
Item {
    id: root
    required property string cardId
    required property var cfg
    required property var theme
    required property int spanW
    required property int spanH
    property bool editing: false
    property Component content: null

    signal tapped
    signal holdRequested
    signal closeRequested
    signal removeRequested
    signal moveStarted
    signal moveUpdated(real dx, real dy)
    signal moveEnded
    signal resizeStarted
    signal resizeUpdated(real dx, real dy)
    signal resizeEnded

    readonly property real radius: (root.cfg?.unit ?? 72) / 2
    readonly property string form: {
        if (root.spanW === 1 && root.spanH === 1)
            return "small";
        if (root.spanH === 1)
            return "wide";
        if (root.spanW === 1)
            return "tall";
        if (root.spanW === root.spanH)
            return "large";
        return root.spanW > root.spanH ? "panorama" : "tall";
    }
    readonly property bool lifted: body.moving || handle.pressed

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.theme?.cardBg ?? "#1C1C1E"
    }

    // Tap: the content's own action (activate()), then the signal.
    function activate(): void {
        if (loader.item && typeof loader.item.activate === "function")
            loader.item.activate();
        root.tapped();
    }

    // Grid coords of a press, stable while the card itself moves under it.
    function gridPos(area: Item, mx: real, my: real): point {
        return area.mapToItem(root.parent, mx, my);
    }

    MouseArea {
        id: body
        anchors.fill: parent
        pressAndHoldInterval: root.cfg?.holdMs ?? 450
        property point start
        property bool moving: false
        property bool swiped: false
        property bool held: false

        onPressed: mouse => {
            start = root.gridPos(body, mouse.x, mouse.y);
            moving = false;
            swiped = false;
            held = false;
        }
        onPressAndHold: {
            if (root.editing || swiped)
                return;
            held = true;
            root.holdRequested();
        }
        onPositionChanged: mouse => {
            const p = root.gridPos(body, mouse.x, mouse.y);
            const dx = p.x - start.x;
            const dy = p.y - start.y;
            if (root.editing) {
                if (!moving && Math.hypot(dx, dy) > 4) {
                    moving = true;
                    root.moveStarted();
                }
                if (moving)
                    root.moveUpdated(dx, dy);
            } else if (!swiped && !held && dy < -(root.cfg?.closeDistance ?? 30)) {
                swiped = true;
                root.closeRequested();
            }
        }
        onReleased: {
            if (moving) {
                moving = false;
                root.moveEnded();
            } else if (!root.editing && !swiped && !held) {
                root.activate();
            }
        }
        onCanceled: {
            if (moving) {
                moving = false;
                root.moveEnded();
            }
        }
    }

    Loader {
        id: loader
        anchors.fill: parent
        sourceComponent: root.content
        enabled: !root.editing
        opacity: root.editing ? 0.7 : 1
        Behavior on opacity { Spring { eps: 0.01 } }
        onLoaded: item.card = root
    }

    // Edit decorations ------------------------------------------------------

    // Resize arc: concentric with the bottom-right corner rounding.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: root.editing ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { Spring { eps: 0.01 } }

        ShapePath {
            fillColor: "transparent"
            strokeColor: "white"
            strokeWidth: 3
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.width - root.radius
                centerY: root.height - root.radius
                radiusX: root.radius - 5
                radiusY: root.radius - 5
                startAngle: 15
                sweepAngle: 60
            }
        }
    }
    MouseArea {
        id: handle
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: root.radius
        height: root.radius
        enabled: root.editing
        cursorShape: Qt.SizeFDiagCursor
        property point start
        onPressed: mouse => {
            start = root.gridPos(handle, mouse.x, mouse.y);
            root.resizeStarted();
        }
        onPositionChanged: mouse => {
            const p = root.gridPos(handle, mouse.x, mouse.y);
            root.resizeUpdated(p.x - start.x, p.y - start.y);
        }
        onReleased: root.resizeEnded()
        onCanceled: root.resizeEnded()
    }

    // "−" badge, top-left, half outside the card (iOS).
    Rectangle {
        id: badge
        x: -4
        y: -4
        width: 22
        height: 22
        radius: 11
        color: "#48484A"
        scale: root.editing && !root.lifted ? 1 : 0
        visible: scale > 0.01
        Behavior on scale { Spring { eps: 0.01 } }

        Rectangle {
            anchors.centerIn: parent
            width: 10
            height: 2
            radius: 1
            color: "white"
        }
        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            onClicked: root.removeRequested()
        }
    }
}
