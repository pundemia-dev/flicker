import QtQuick
import Quickshell
import Quickshell.Wayland

// Idle dim / screen-off shade of one output (services/Idle): black over
// everything (the island and the lock too: Overlay, created after them),
// eased to idle.shadeFor(output) in idle.shadeMs. The built-in panel dims
// its backlight instead and only gets the shade at screen-off. No input:
// the mask is empty, so the first click after a dim lands where it was
// aimed (the compositor counts it as activity and the shade lifts).
PanelWindow {
    id: root
    // Not `screen`: that shadows WindowInterface.screen (see Island.qml).
    required property ShellScreen targetScreen
    required property var idle
    screen: root.targetScreen

    readonly property real target: root.idle.shadeFor(root.targetScreen?.name ?? "")

    visible: root.target > 0 || shade.opacity > 0
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "flicker-idle"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    mask: Region {}

    Rectangle {
        id: shade
        anchors.fill: parent
        color: "black"
        opacity: root.target
        Behavior on opacity {
            NumberAnimation {
                duration: root.idle.shadeMs
                easing.type: Easing.OutCubic
            }
        }
    }
}
