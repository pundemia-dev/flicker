import QtQuick

// Hyprland backend stub (spec: implement later, keep the facade interface).
QtObject {
    property bool fullscreen: false
    property int workspace: 1
    property int workspaceCount: 1
    property var perScreen: ({})
    property string focusedOutput: ""
    function grabFocus(): void {}
    function releaseFocus(): void {}
    function spawn(cmd: string): void {}
    function screenshot(region: string): void {}
    function runRegionCapture(mode: string): void {}
}
