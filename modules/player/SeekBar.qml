import QtQuick
import "../../components"
import "../../config"

// Seekable progress bar (player module + QS media card). Press/drag scrubs
// a LOCAL position (the bar and `shownPosition` follow the pointer, the bar
// thickens like iOS); release seeks once (MprisPlayer.position is
// writable when canSeek) — seeking on every move would spam D-Bus. After
// release the target is held until the player reports a position near it
// (or `holdMs` passes), so the bar does not snap back to the old position
// for a frame while the seek round-trips. Dragging past an end stretches
// the bar toward it (rubber band, Config.seekBar; same look as the OSD's
// push), following the pointer with diminishing give, spring back on release.
// `labelColor` = colour for the owner's time labels (white while held).
Item {
    id: root
    property var player: null
    property var haptics: null
    // Past an end right now (release haptic fires once per crossing).
    property bool pastEnd: false
    property real position: 0
    property real length: 0
    property bool lengthKnown: false
    property color trackColor: "#33FFFFFF"
    property color fillColor: "#F0F4FB"
    // Extra hit area above/below the thin bar (px).
    property real hitPad: 8
    property int holdMs: 1200

    readonly property bool canSeek: (root.player?.canSeek ?? false) && (root.player?.positionSupported ?? false) && root.lengthKnown
    readonly property bool dragging: ma.pressed && root.canSeek
    property real dragFrac: 0
    property real pending: -1
    readonly property var cfg: Config.data.seekBar
    // Signed stretch fraction (<0 = past the start, >0 = past the end).
    property real stretch: 0
    Behavior on stretch {
        enabled: !ma.pressed
        Spring {
            stiffness: root.cfg.stretchStiffness
            damp: root.cfg.stretchDamping
            eps: 0.001
        }
    }

    // Time labels (elapsed / remaining) light up from dim grey to white
    // while the bar is held (spring-mixed, no timed transition).
    property color labelDim: "#B3EBEBF5"
    property color labelLit: "#FFFFFF"
    property real lit: ma.pressed ? 1 : 0
    Behavior on lit { Spring { stiffness: 5; damp: 0.5; eps: 0.01 } }
    readonly property color labelColor: Qt.rgba(
        root.labelDim.r + (root.labelLit.r - root.labelDim.r) * root.lit,
        root.labelDim.g + (root.labelLit.g - root.labelDim.g) * root.lit,
        root.labelDim.b + (root.labelLit.b - root.labelDim.b) * root.lit,
        root.labelDim.a + (root.labelLit.a - root.labelDim.a) * root.lit)

    // What the bar and the time labels should show.
    readonly property real shownPosition: root.dragging ? root.dragFrac * root.length
        : (root.pending >= 0 ? root.pending : root.position)

    onPositionChanged: {
        if (root.pending >= 0 && Math.abs(root.position - root.pending) < 1.5)
            root.pending = -1;
    }

    Item {
        id: thick
        // Thickens while scrubbing.
        height: root.height * (root.dragging ? 1.6 : 1)
        Behavior on height { Spring { eps: 0.05 } }
    }
    ProgressBar {
        anchors.verticalCenter: parent.verticalCenter
        // Stretch grows the bar toward the pulled end and thins it a little.
        width: parent.width * (1 + Math.abs(root.stretch))
        x: root.stretch < 0 ? -(width - parent.width) : 0
        height: thick.height * (1 - Math.abs(root.stretch) * 1.5)
        value: root.lengthKnown ? Math.min(1, root.shownPosition / root.length) : 0
        trackColor: root.trackColor
        fillColor: root.fillColor
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        anchors.topMargin: -root.hitPad
        anchors.bottomMargin: -root.hitPad
        enabled: root.canSeek
        cursorShape: root.canSeek ? Qt.PointingHandCursor : Qt.ArrowCursor
        function scrub(mx: real): void {
            root.dragFrac = Math.max(0, Math.min(1, mx / width));
            const over = mx < 0 ? mx : (mx > width ? mx - width : 0);
            const o = Math.abs(over) / Math.max(1, width);
            root.stretch = Math.sign(over) * root.cfg.stretchMax * o / (o + root.cfg.stretchSoftness);
            if (over !== 0 && !root.pastEnd && root.canSeek && Config.data.haptics?.limits)
                root.haptics?.release();
            root.pastEnd = over !== 0;
        }
        onPressed: mouse => scrub(mouse.x)
        onPositionChanged: mouse => scrub(mouse.x)
        onCanceled: { root.stretch = 0; root.pastEnd = false; }
        onReleased: {
            root.stretch = 0;
            root.pastEnd = false;
            if (!root.player)
                return;
            root.pending = root.dragFrac * root.length;
            root.player.position = root.pending;
            hold.restart();
        }
    }
    Timer {
        id: hold
        interval: root.holdMs
        onTriggered: root.pending = -1
    }
}
