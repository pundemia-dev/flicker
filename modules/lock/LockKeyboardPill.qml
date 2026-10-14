import QtQuick
import "../../components"
import "../keyboard"

// The keyboard pill on the lock screen: the session lock hides every other
// surface (KeyboardOverlay included), so it is drawn here, under the
// password field's caret (LockField.caretX: past the last dot). Caps Lock shows for as long as it
// is on (macOS at a caret), a layout switch for `keyboard.layoutShowMs`
// (services/KeyboardIndicator `flashing`); the pointer probe of the desktop
// path is not used. Background = the wallpaper accent, as on the desktop.
Item {
    id: root

    property var keyboard: null
    property var theme: null
    // The password field (LockField): the pill rides under it.
    property Item field: null
    property bool active: false

    readonly property var cfg: root.keyboard?.cfg ?? ({})
    readonly property string what: !(root.keyboard?.enabled ?? false) ? ""
        : root.keyboard.flashing ? "layout"
        : (root.keyboard.caps && (root.cfg.caps ?? true)) ? "caps" : ""
    property string heldWhat: "caps"
    onWhatChanged: if (root.what !== "")
        root.heldWhat = root.what

    readonly property real gap: root.keyboard?.cfg?.lockGap ?? 14

    KeyboardPill {
        id: pill
        // Under the field's caret (follows the dot row as it grows/shrinks).
        x: (root.field?.x ?? 0) + (root.field?.caretX ?? 0) - pill.width / 2
        y: (root.field?.y ?? 0) + (root.field?.height ?? 0) + root.gap - pill.margin
        shown: root.active && root.what !== ""
        what: root.heldWhat
        label: root.keyboard?.label ?? ""
        cfg: root.cfg
        theme: root.theme
        bg: tint.value
    }

    SpringColor {
        id: tint
        target: root.theme?.wallAccentOn ? root.theme.wallAccent : (root.theme?.keyboardPillBg ?? "#E5E5EA")
    }
}
