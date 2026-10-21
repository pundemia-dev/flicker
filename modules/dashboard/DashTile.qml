import QtQuick
import "../../components"
import "../quicksettings"

// One dashboard grid slot: the card (content Loader, fills the slot) plus
// the edit-mode chrome of Quick Settings (modules/quicksettings/QsCard):
// blinking rim, bottom-right resize arc, "−" badge. Geometry comes from the
// module; this file only reports gestures.
//
// Outside edit mode the tile takes NO presses (every MouseArea is disabled):
// they fall through to the card's own controls or, below the island
// content, to GestureZones (swipe-up close). Edit mode: card content is
// disabled, the body drags the card (move*), the arc resizes it (resize*),
// the badge hides it.
Item {
    id: root
    required property string cardId
    // DashMetrics.edit(Config.dashboard) + the card corner radius.
    required property var editCfg
    required property real radius
    required property var theme
    property bool editing: false
    property Component content: null

    signal removeRequested
    signal moveStarted
    // dx/dy in grid coords (the tile's parent), stable while the tile moves.
    signal moveUpdated(real dx, real dy)
    signal moveEnded
    signal resizeStarted
    signal resizeUpdated(real dx, real dy)
    signal resizeEnded

    readonly property bool lifted: body.moving || handle.pressed

    function gridPos(area: Item, mx: real, my: real): point {
        return area.mapToItem(root.parent, mx, my);
    }

    Loader {
        id: loader
        anchors.fill: parent
        sourceComponent: root.content
        // Hidden cards are not loaded (Updates polls checkupdates); the
        // tile stays visible through its scale-out, so the content goes too.
        active: root.visible
        enabled: !root.editing
    }

    MouseArea {
        id: body
        anchors.fill: parent
        enabled: root.editing
        property point start
        property bool moving: false

        onPressed: mouse => {
            start = root.gridPos(body, mouse.x, mouse.y);
            moving = false;
        }
        onPositionChanged: mouse => {
            const p = root.gridPos(body, mouse.x, mouse.y);
            const dx = p.x - start.x;
            const dy = p.y - start.y;
            if (!moving && Math.hypot(dx, dy) > 4) {
                moving = true;
                root.moveStarted();
            }
            if (moving)
                root.moveUpdated(dx, dy);
        }
        onReleased: {
            if (moving) {
                moving = false;
                root.moveEnded();
            }
        }
        onCanceled: {
            if (moving) {
                moving = false;
                root.moveEnded();
            }
        }
    }

    // Edit rim: inner border that blinks clear -> darker than the card and
    // back (QsCard's rim; a timed loop, springs cannot loop).
    Rectangle {
        id: rim
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: root.editCfg.rimWidth
        border.color: root.theme?.qsEditRim ?? "transparent"
        opacity: root.editing ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { Spring { eps: 0.01 } }

        SequentialAnimation on border.color {
            running: rim.visible
            loops: Animation.Infinite
            ColorAnimation {
                to: root.theme?.qsEditRimDim ?? "#B3000000"
                duration: root.editCfg.rimBlinkMs
                easing.type: Easing.InOutSine
            }
            ColorAnimation {
                to: root.theme?.qsEditRim ?? "transparent"
                duration: root.editCfg.rimBlinkMs
                easing.type: Easing.InOutSine
            }
        }
    }

    // Resize arc on the bottom-right corner rounding (see QsResizeArc).
    QsResizeArc {
        anchors.fill: parent
        cx: root.width - root.radius
        cy: root.height - root.radius
        radius: root.radius
        thickness: root.editCfg.arcWidth
        endRadius: root.radius - rim.border.width
        curve: root.editCfg.arcCurve
        opacity: root.editing ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { Spring { eps: 0.01 } }
    }
    MouseArea {
        id: handle
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        // Larger than the corner rounding: the dashboard radius is small.
        width: Math.max(root.radius, 32)
        height: width
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
            enabled: root.editing
            onClicked: root.removeRequested()
        }
    }
}
