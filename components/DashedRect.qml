import QtQuick

// Rounded rectangle outlined with a dashed stroke (pShell port). Canvas 2D:
// Rectangle borders cannot dash.
Canvas {
    id: root

    property color strokeColor: "#0F7CEC"
    property real strokeWidth: 2
    property real dashLength: 10
    property real gapLength: 6
    property real cornerRadius: 4

    onStrokeColorChanged: requestPaint()
    onStrokeWidthChanged: requestPaint()
    onDashLengthChanged: requestPaint()
    onGapLengthChanged: requestPaint()
    onCornerRadiusChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        if (!ctx)
            return;
        ctx.reset();
        const inset = Math.max(0.5, root.strokeWidth / 2);
        const w = Math.max(0, root.width - inset * 2);
        const h = Math.max(0, root.height - inset * 2);
        const r = Math.max(0, Math.min(root.cornerRadius, Math.min(w, h) / 2));
        ctx.beginPath();
        ctx.moveTo(inset + r, inset);
        ctx.lineTo(inset + w - r, inset);
        ctx.arcTo(inset + w, inset, inset + w, inset + r, r);
        ctx.lineTo(inset + w, inset + h - r);
        ctx.arcTo(inset + w, inset + h, inset + w - r, inset + h, r);
        ctx.lineTo(inset + r, inset + h);
        ctx.arcTo(inset, inset + h, inset, inset + h - r, r);
        ctx.lineTo(inset, inset + r);
        ctx.arcTo(inset, inset, inset + r, inset, r);
        ctx.closePath();
        ctx.setLineDash([Math.max(0.1, root.dashLength), Math.max(0.1, root.gapLength)]);
        ctx.lineWidth = root.strokeWidth;
        ctx.lineCap = "round";
        ctx.strokeStyle = root.strokeColor;
        ctx.stroke();
    }
}
