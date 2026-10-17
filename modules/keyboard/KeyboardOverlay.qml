import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../components"
import "../../config"

// Per-screen home of the keyboard pill (services/KeyboardIndicator): a
// full-screen transparent Overlay surface with an EMPTY input region (never
// takes a click), mapped only while the pill shows here. The pill sits
// `gap` below the text caret (services/Caret) — above it when the screen
// has no room below — or, with no focused text field, below the mouse
// pointer; always clamped `edgeMargin` inside the screen. Moves on springs
// (caret typing, a pointer elsewhere on the next show); the first
// appearance lands in place without a flight.
// The pointer probe is a second surface: full-screen WITH input, mapped only
// while `keyboard.probing` (a few ms) — mapping it makes the compositor send
// wl_pointer.enter at the pointer position.
Scope {
    id: root
    required property ShellScreen targetScreen
    required property var keyboard
    required property var theme
    required property var lock
    required property var compositor

    readonly property var cfg: Config.data.keyboard ?? ({})
    readonly property string name: root.targetScreen.name
    readonly property var caret: root.keyboard.caret?.anchor ?? null
    readonly property var ptr: root.keyboard.pointer
    // Output the pill belongs to now.
    readonly property string host: root.caret ? root.caret.output
        : (root.ptr ? root.ptr.output : (root.compositor.focusedOutput ?? ""))
    readonly property bool here: root.host === root.name
    // Last non-empty content, held while the pill fades out.
    property string heldWhat: "caps"
    Connections {
        target: root.keyboard
        function onWhatChanged(): void {
            if (root.keyboard.what !== "")
                root.heldWhat = root.keyboard.what;
        }
    }
    readonly property bool wantShown: root.here && root.keyboard.what !== "" && !root.keyboard.probing && !root.lock.locked

    PanelWindow {
        id: win
        screen: root.targetScreen
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "flicker-keyboard"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true
        mask: Region {}
        visible: root.wantShown || pill.p > 0.01

        // The thing to sit under: the caret, else the pointer (its arrow
        // is `pointerHeight` tall), else the screen's lower part.
        readonly property var target: {
            if (root.caret)
                return root.caret;
            if (root.ptr && root.ptr.output === root.name)
                return { x: root.ptr.x, y: root.ptr.y, width: 0, height: root.cfg.pointerHeight ?? 22 };
            return { x: win.width / 2, y: win.height * (root.cfg.fallbackY ?? 0.8), width: 0, height: 0 };
        }
        readonly property real m: root.cfg.edgeMargin ?? 8
        readonly property real gap: root.cfg.gap ?? 6
        readonly property real w: pill.targetWidth
        readonly property real h: pill.pillHeight
        readonly property real below: target.y + target.height + gap
        // Capsule top-left (target values; the springs animate pill x/y).
        readonly property real capX: Math.max(m, Math.min(win.width - m - w, target.x + target.width / 2 - w / 2))
        readonly property real capY: {
            const y = below + h + m <= win.height ? below : target.y - gap - h;
            return Math.max(m, Math.min(win.height - m - h, y));
        }

        // Capsule CENTRE on springs (targets only read target values — a
        // target reading the animated width would restart the spring every
        // frame); the pill centres itself on it while its width springs.
        Item {
            id: spot
            // Springs only while on show: a fresh pill lands in place.
            readonly property bool moving: pill.p > 0.01
            x: Math.round(win.capX + win.w / 2)
            y: Math.round(win.capY + win.h / 2)
            Behavior on x {
                enabled: spot.moving
                Spring { stiffness: root.cfg.moveSpring ?? 3.5; damp: root.cfg.moveDamping ?? 0.38 }
            }
            Behavior on y {
                enabled: spot.moving
                Spring { stiffness: root.cfg.moveSpring ?? 3.5; damp: root.cfg.moveDamping ?? 0.38 }
            }

            KeyboardPill {
                id: pill
                x: -width / 2
                y: -height / 2
                shown: root.wantShown
                what: root.heldWhat
                label: root.keyboard.label
                cfg: root.cfg
                theme: root.theme
                bg: tint.value
            }
        }

        SpringColor {
            id: tint
            target: root.theme.wallAccentOn ? root.theme.wallAccent : root.theme.keyboardPillBg
        }
    }

    // Pointer probe (see header).
    PanelWindow {
        id: probe
        screen: root.targetScreen
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "flicker-keyboard-probe"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true
        visible: root.keyboard.probing && !root.lock.locked

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onPositionChanged: m => root.keyboard.pointerSeen(root.name, m.x, m.y)
            onContainsMouseChanged: if (containsMouse) root.keyboard.pointerSeen(root.name, mouseX, mouseY)
        }
    }
}
