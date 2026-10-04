import QtQuick
import Quickshell
import Quickshell.Wayland
import "editor"
import "color"
import "window"

// Per-screen capture surface. Layers: frozen backdrop (live hole over the
// island band) → dim (cut around the tool's selection / hovered window) →
// global crosshair → the mode's tool (region editor / colour loupe / window
// picker) → the chasing square. The square and crosshair are the SAME
// global state on every screen shifted by this screen's origin, so they
// cross monitors seamlessly. A tool lives on every screen until one claims
// the session (selection / colour panel), then only on that one.
PanelWindow {
    id: root
    required property ShellScreen targetScreen
    required property var capture
    required property var motion
    required property var theme

    readonly property var cfg: root.capture.cfg
    readonly property string name: root.targetScreen.name
    readonly property real ox: root.targetScreen.x
    readonly property real oy: root.targetScreen.y
    readonly property real dpr: root.targetScreen.devicePixelRatio ?? 1
    readonly property Item tool: toolLoader.item
    readonly property real cx: root.motion.cursorX - root.ox
    readonly property real cy: root.motion.cursorY - root.oy

    screen: root.targetScreen
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "pillShell-capture"
    // Only the screen being worked on takes the keyboard (one exclusive
    // surface; text annotations / the colour field type into it).
    WlrLayershell.keyboardFocus: root.capture.activeScreen === root.name ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    // Base input while another screen owns the session (no tool here):
    // hover keeps the global crosshair/square alive, a click hands the
    // session back to "any screen" so the next drag starts here.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.CrossCursor
        onPositionChanged: mouse => root.capture.pointerAt(root.ox + mouse.x, root.oy + mouse.y)
        onPressed: mouse => mouse.button === Qt.RightButton ? root.capture.cancel() : root.capture.claim("")
        onWheel: wheel => root.capture.cycle(wheel.angleDelta.y > 0 ? -1 : 1)
    }

    CaptureBackdrop {
        anchors.fill: parent
        source: root.capture.grabbed ? "file://" + root.capture.srcFor(root.name) : ""
        hole: root.capture.holeOn(root.name)
    }

    CaptureDim {
        anchors.fill: parent
        cut: root.tool?.cutRect ?? null
        color: root.theme.captureDim
        opacity: root.motion.dimLevel * root.cfg.dimOpacity * ((root.tool?.dimmed ?? true) ? 1 : 0)
    }

    Item {
        anchors.fill: parent
        opacity: root.motion.crossLevel * root.cfg.crosshairOpacity
        visible: opacity > 0.001

        Rectangle {
            x: Math.round(root.cx - width / 2)
            width: root.cfg.crosshairWidth
            height: parent.height
            color: root.theme.captureCross
        }
        Rectangle {
            y: Math.round(root.cy - height / 2)
            width: parent.width
            height: root.cfg.crosshairWidth
            color: root.theme.captureCross
        }
    }

    Loader {
        id: toolLoader
        anchors.fill: parent
        // Kept through the fade-out (fades with the dim): unloading at
        // `closing` dropped the selection cut, so the whole screen flashed
        // dim and the toolbar popped away.
        active: root.capture.active && (root.capture.editScreen === "" || root.capture.editScreen === root.name)
        enabled: !root.capture.closing
        opacity: root.capture.closing ? root.motion.dimLevel : 1
        sourceComponent: root.capture.mode === "color" ? colorComp
            : (root.capture.mode === "window" ? windowComp : editorComp)
    }

    Component {
        id: editorComp
        RegionEditor {
            capture: root.capture
            actions: root.capture.actions
            theme: root.theme
            cfg: root.cfg
            screenName: root.name
            ox: root.ox
            oy: root.oy
            dpr: root.dpr
            srcPath: root.capture.srcFor(root.name)
            keyTarget: keyRoot
            Component.onCompleted: {
                const p = root.capture.takePreset(root.name);
                if (p)
                    setSelection(p);
            }
        }
    }

    Component {
        id: colorComp
        ColorLoupe {
            capture: root.capture
            actions: root.capture.actions
            theme: root.theme
            cfg: root.cfg
            screenName: root.name
            ox: root.ox
            oy: root.oy
            dpr: root.dpr
            srcPath: root.capture.srcFor(root.name)
            keyTarget: keyRoot
        }
    }

    Component {
        id: windowComp
        WindowPicker {
            capture: root.capture
            theme: root.theme
            cfg: root.cfg
            screenName: root.name
            ox: root.ox
            oy: root.oy
        }
    }

    CaptureSquare {
        visible: root.capture.stolen && opacity > 0.001
        opacity: root.motion.squareLevel
        x: root.motion.centerX - root.ox - width / 2
        y: root.motion.centerY - root.oy - height / 2
        width: root.motion.w
        height: root.motion.h
        radius: root.motion.r
        tipRadius: root.motion.rTip
        theme: root.theme
        cfg: root.cfg
        glyph: root.capture.glyph(root.capture.mode)
        glyphColor: root.capture.glyphColor(root.capture.mode)
        swapKey: root.capture.mode
        iconShown: root.motion.chasing || root.motion.flight >= root.cfg.iconAt
    }

    // Keys: the tool first (editor shortcuts, Esc chain), then the session.
    Item {
        id: keyRoot
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            const t = root.tool;
            event.accepted = true;
            if (event.key === Qt.Key_Escape) {
                if (!(t?.handleEscape() ?? false))
                    root.capture.cancel();
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                t?.confirm();
            } else if (t?.handleKey(event) ?? false) {
                return;
            } else if (event.key === Qt.Key_Tab && !root.capture.hasSelection) {
                root.capture.cycle(1);
            } else if (event.key === Qt.Key_Backtab && !root.capture.hasSelection) {
                root.capture.cycle(-1);
            } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9 && !root.capture.hasSelection) {
                root.capture.setMode(event.key - Qt.Key_1);
            } else {
                event.accepted = false;
            }
        }
    }
}
