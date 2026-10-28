import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../components"
import "../../config"
import "../keyboard"

// Per-screen home of the translator's selection pill + panel
// (services/Translator). One full-screen transparent Overlay surface,
// mapped only while something shows here; its input region is the pill
// capsule while the pill is up, the whole screen while the panel is open
// (a press outside closes it, like a popup) and nothing otherwise. The
// panel holds the keyboard (Exclusive) while open. The pill = the keyboard
// pill (KeyboardPill, wallpaper-accent capsule) with a translate glyph,
// placed like KeyboardOverlay places it: under the anchor (pointer / caret),
// above when no room, clamped `edgeMargin` inside the screen.
// The pointer probe is a second surface, full-screen WITH input, mapped
// while `translator.probing` — its wl_pointer.enter arrives once the mouse
// button that made the selection is released (see Translator).
Scope {
    id: root
    required property ShellScreen targetScreen
    required property var translator
    required property var theme
    required property var lock

    readonly property var cfg: root.translator.cfg.selection ?? ({})
    readonly property var pillCfg: Object.assign({}, Config.data.keyboard ?? ({}), root.cfg.pill ?? ({}))
    readonly property string name: root.targetScreen.name
    readonly property bool here: (root.translator.anchor?.output ?? "") === root.name
    readonly property bool pillWanted: root.here && root.translator.pillShown && !root.lock.locked
    readonly property bool panelWanted: root.here && root.translator.panelOpen && !root.lock.locked

    PanelWindow {
        id: win
        screen: root.targetScreen
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "flicker-translator"
        WlrLayershell.keyboardFocus: root.panelWanted ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true
        visible: root.pillWanted || pill.p > 0.01 || root.panelWanted || panel.shownNow
        mask: root.panelWanted ? fullRegion : (root.pillWanted ? pillRegion : emptyRegion)

        Region { id: emptyRegion }
        Region { id: fullRegion; item: catcher }
        Region { id: pillRegion; item: pillHit }

        // Outside the panel: a press closes it.
        MouseArea {
            id: catcher
            anchors.fill: parent
            enabled: root.panelWanted
            onPressed: root.translator.closePanel()
        }

        readonly property var target: root.translator.anchor ?? { x: win.width / 2, y: win.height / 3, width: 0, height: 0 }
        readonly property real m: root.pillCfg.edgeMargin ?? 8
        readonly property real gap: root.pillCfg.gap ?? 6
        readonly property real w: pill.targetWidth
        readonly property real h: pill.pillHeight
        readonly property real below: target.y + target.height + gap
        readonly property real capX: Math.max(m, Math.min(win.width - m - w, target.x + target.width / 2 - w / 2))
        readonly property real capY: {
            const y = below + h + m <= win.height ? below : target.y - gap - h;
            return Math.max(m, Math.min(win.height - m - h, y));
        }

        // Capsule centre on springs (KeyboardOverlay): a new selection
        // while the pill is up glides it over; a fresh one lands in place.
        Item {
            id: spot
            readonly property bool moving: pill.p > 0.01
            x: Math.round(win.capX + win.w / 2)
            y: Math.round(win.capY + win.h / 2)
            Behavior on x {
                enabled: spot.moving
                Spring { stiffness: root.pillCfg.moveSpring ?? 3.5; damp: root.pillCfg.moveDamping ?? 0.38 }
            }
            Behavior on y {
                enabled: spot.moving
                Spring { stiffness: root.pillCfg.moveSpring ?? 3.5; damp: root.pillCfg.moveDamping ?? 0.38 }
            }

            KeyboardPill {
                id: pill
                x: -width / 2
                y: -height / 2
                shown: root.pillWanted
                what: "layout"
                glyph: "" // tabler language
                label: I18n.tr("Translate")
                cfg: root.pillCfg
                theme: root.theme
                bg: hit.containsMouse ? Qt.lighter(tint.value, 1.12) : tint.value
                // Gone at once when the panel takes over (it grows from here).
                opacity: root.panelWanted ? 0 : 1

                Item {
                    id: pillHit
                    anchors.centerIn: parent
                    width: pill.capsuleWidth
                    height: pill.pillHeight
                    MouseArea {
                        id: hit
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: root.translator.pillHovered = containsMouse
                        onClicked: {
                            const p = pillHit.mapToItem(win.contentItem, 0, 0);
                            root.translator.growFrom = { x: p.x, y: p.y, w: pillHit.width, h: pillHit.height, color: pill.bg };
                            root.translator.openPanel();
                        }
                    }
                }
            }
        }

        SpringColor {
            id: tint
            target: root.theme.wallAccentOn ? root.theme.wallAccent : root.theme.keyboardPillBg
        }

        TranslatorPanel {
            id: panel
            anchors.fill: parent
            translator: root.translator
            theme: root.theme
            open: root.panelWanted
            growFrom: root.translator.growFrom
        }
    }

    // Pointer probe (see header).
    PanelWindow {
        id: probe
        screen: root.targetScreen
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "flicker-translator-probe"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true
        visible: root.translator.probing && !root.lock.locked

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onPositionChanged: m => root.translator.pointerSeen(root.name, m.x, m.y)
            onContainsMouseChanged: if (containsMouse) root.translator.pointerSeen(root.name, mouseX, mouseY)
        }
    }
}
