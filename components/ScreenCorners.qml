import QtQuick

// Fake rounded monitor corners: 4 concave pieces in `color`, one per corner of
// the parent, so the visible area appears rounded. Fill the screen with it.
Item {
    id: root

    property color color: "#101115"
    property real radius: 16

    Repeater {
        model: 4

        delegate: CornerPiece {
            required property int index
            color: root.color
            radius: root.radius
            visible: radius > 0
            x: index === 0 || index === 3 ? 0 : root.width - width
            y: index < 2 ? 0 : root.height - height
            rotation: index * 90
            transformOrigin: Item.Center
        }
    }

    // Draws the top-left concave piece; other corners rotate this one.
    component CornerPiece: Canvas {
        id: cp
        property color color
        property real radius
        width: radius
        height: radius

        onColorChanged: requestPaint()

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
