import QtQuick
import Quickshell
import Quickshell.Wayland
import "../components"
import "../config"

// Fake rounded monitor corners: 4 concave pieces drawn in the bezel colour, one
// per corner, so the visible screen area appears rounded. The window has an
// empty input mask so it never swallows clicks.
PanelWindow {
    id: root
    // Not `screen`: that shadows WindowInterface.screen (see Island.qml).
    required property ShellScreen targetScreen
    screen: root.targetScreen
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    readonly property var cornersCfg: Config.data.corners

    mask: Region {}

    ScreenCorners {
        anchors.fill: parent
        color: root.cornersCfg.color
        radius: root.cornersCfg.enabled ? root.cornersCfg.rounding : 0
    }
}
