import QtQuick
import "../../components"
import "../../config"

// Grid of choice chips (languages / engines) for the translator; the
// current one is accent-filled. Wheel-scrolls when taller than its box
// (no Flickable: presses stay with the chips).
Item {
    id: root
    required property var theme
    // [{ id, name }]
    property var options: []
    property string current: ""
    signal picked(string id)

    readonly property real contentHeight: flow.implicitHeight
    clip: true

    readonly property real maxScroll: Math.max(0, flow.implicitHeight - root.height)
    property real scroll: 0
    onOptionsChanged: root.scroll = 0

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            const delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 2;
            root.scroll = Math.max(0, Math.min(root.maxScroll, root.scroll - delta));
        }
    }

    Flow {
        id: flow
        width: root.width
        property real scrollY: root.scroll
        Behavior on scrollY { Spring { stiffness: 6; damp: 0.6 } }
        y: -scrollY
        spacing: 6
        Repeater {
            model: root.options
            LangChip {
                required property var modelData
                theme: root.theme
                text: modelData.name
                checked: modelData.id === root.current
                onClicked: root.picked(modelData.id)
            }
        }
    }
}
