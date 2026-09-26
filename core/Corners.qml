import QtQuick
import Quickshell
import Quickshell.Wayland
import "../config"

// Fake rounded monitor corners: 4 concave pieces drawn in the bezel colour, one
// per corner, so the visible screen area appears rounded. The window has an
// empty input mask so it never swallows clicks.
PanelWindow {
    id: root
    required property ShellScreen screen
    screen: root.screen
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    readonly property var cornersCfg: Config.data.corners

    mask: Region {}

    Repeater {
        model: 4

        delegate: CornerPiece {
            required property int index
            color: root.cornersCfg.color
            radius: root.cornersCfg.enabled ? root.cornersCfg.rounding : 0
            visible: radius > 0
            x: index === 0 || index === 3 ? 0 : parent.width - width
            y: index < 2 ? 0 : parent.height - height
            rotation: index * 90
            transformOrigin: Item.Center
        }
    }

    // Draws the top-left concave piece; other corners rotate this one.
    component CornerPiece: Canvas {
        id: cp
        property color color: "#101115"
        property real radius: 16
        width: radius
        height: radius

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            if (cp.radius <= 0)
                return;
            const w = cp.width, h = cp.height;
            ctx.fillStyle = cp.color;
            ctx.beginPath();
            ctx.moveTo(0, h);
            ctx.lineTo(0, 0);
            ctx.lineTo(w, 0);
            ctx.arc(w, h, w, -Math.PI / 2, Math.PI, true);
            ctx.closePath();
            ctx.fill();
        }
    }
}
