import QtQuick

// Window mode on one screen: the window under the cursor is highlighted
// (rects from the compositor facade, read once when the overlay opens —
// the screen is frozen anyway); a click hands its rect to the region editor
// as a ready selection (shot mode), so annotations / OCR / copy all apply.
// Replaces pShell's niri-only pick-window: works wherever the backend
// reports window geometry (niri, driftwm).
Item {
    id: root
    required property var capture
    required property var theme
    required property var cfg
    required property string screenName
    required property real ox
    required property real oy

    // Snapshot at open (the screen is frozen); clipped to the screen on use.
    property var rects: []
    Component.onCompleted: root.rects = root.capture.compositor.windowRects(root.screenName)
    property real cursorX: -1
    property real cursorY: -1
    // Focused window first (backends sort it first), then the first hit.
    readonly property var hovered: {
        let best = null;
        for (const r of root.rects) {
            if (root.cursorX < r.x || root.cursorX > r.x + r.width || root.cursorY < r.y || root.cursorY > r.y + r.height)
                continue;
            if (!best)
                best = r;
        }
        if (!best)
            return null;
        const x = Math.max(0, best.x), y = Math.max(0, best.y);
        return Qt.rect(x, y, Math.min(best.x + best.width, root.width) - x, Math.min(best.y + best.height, root.height) - y);
    }

    // ── Tool contract (CaptureOverlay) ──────────────────────────────
    readonly property var cutRect: root.hovered
    readonly property bool dimmed: true
    readonly property bool hasSelection: false

    function handleEscape(): bool {
        return false;
    }

    function handleKey(event: var): bool {
        return false;
    }

    function confirm(): void {
        if (root.hovered)
            root.capture.pickWindow(root.screenName, root.hovered);
    }

    Rectangle {
        visible: root.hovered !== null
        x: root.hovered?.x ?? 0
        y: root.hovered?.y ?? 0
        width: root.hovered?.width ?? 0
        height: root.hovered?.height ?? 0
        color: "transparent"
        border.width: root.cfg.selectionBorder * 2
        border.color: root.theme.captureSelection
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: root.hovered ? Qt.PointingHandCursor : Qt.CrossCursor
        onPositionChanged: mouse => {
            root.cursorX = mouse.x;
            root.cursorY = mouse.y;
            root.capture.pointerAt(root.ox + mouse.x, root.oy + mouse.y);
        }
        onEntered: {
            root.cursorX = mouseX;
            root.cursorY = mouseY;
        }
        onWheel: wheel => root.capture.cycle(wheel.angleDelta.y > 0 ? -1 : 1)
        onPressed: mouse => {
            if (mouse.button === Qt.RightButton)
                root.capture.cancel();
            else
                root.confirm();
        }
    }
}
