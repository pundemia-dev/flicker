import QtQuick

// Soft pressed подложка shared by TransportBtn/SkipBtn: radial-gradient
// disc (solid core, feathered edge) instead of a hard-edged Rectangle.
// Visible ONLY while pressed — no idle/hover background.
Canvas {
    property bool pressed: false
    anchors.fill: parent
    visible: pressed
    onPressedChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d");
        const cx = width / 2, cy = height / 2, r = width / 2;
        ctx.clearRect(0, 0, width, height);
        const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, r);
        g.addColorStop(0, "#33FFFFFF");
        g.addColorStop(0.85, "#33FFFFFF");
        g.addColorStop(1, "transparent");
        ctx.fillStyle = g;
        ctx.beginPath();
        ctx.arc(cx, cy, r, 0, Math.PI * 2);
        ctx.fill();
    }
}
