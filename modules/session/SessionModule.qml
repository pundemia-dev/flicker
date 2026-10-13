import QtQuick
import "../../components"
import "../../config"
import "SessionActions.js" as SessionActions

// Session menu (lock / log out / sleep / restart / shut down): one row of
// bare glyph buttons (Config.session.actions order), no labels. Destructive
// actions (SessionActions confirm) arm on the first press — the glyph turns
// red and bumps — and run on a second press within `confirmMs`. services/Session runs the action
// after the island has closed.
// Keys: ←/→ (Tab / Shift+Tab) select, Enter/Space press, Esc disarm/close.
Item {
    id: root
    required property var session
    required property var theme
    required property var cfg
    signal closeRequested

    readonly property var actions: SessionActions.known(root.cfg.actions)
    property int selected: Math.max(0, root.actions.indexOf(root.cfg.defaultAction ?? ""))
    property string armed: ""

    onSelectedChanged: root.armed = ""

    function move(d: int): void {
        const n = root.actions.length;
        if (n > 0)
            root.selected = (root.selected + d + n) % n;
    }
    function press(i: int): void {
        const id = root.actions[i];
        if (!id)
            return;
        root.selected = i;
        if (SessionActions.of(id).confirm && (root.cfg.confirm ?? true) && root.armed !== id) {
            root.armed = id;
            disarm.restart();
            return;
        }
        root.armed = "";
        root.session.run(id);
        root.closeRequested();
    }

    Timer {
        id: disarm
        interval: root.cfg.confirmMs ?? 3000
        onTriggered: root.armed = ""
    }

    focus: true
    Component.onCompleted: root.forceActiveFocus()
    Keys.onPressed: event => {
        const k = event.key;
        if (k === Qt.Key_Left || k === Qt.Key_Backtab || (k === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier)))
            root.move(-1);
        else if (k === Qt.Key_Right || k === Qt.Key_Tab)
            root.move(1);
        else if (k === Qt.Key_Home)
            root.selected = 0;
        else if (k === Qt.Key_End)
            root.selected = root.actions.length - 1;
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space)
            root.press(root.selected);
        else if (k === Qt.Key_Escape) {
            if (root.armed !== "")
                root.armed = "";
            else
                root.closeRequested();
        } else
            return;
        event.accepted = true;
    }

    // ONE selection plate under the glyphs, springing to the selected
    // slot; red while armed. Flat (no rim / shadow); radius concentric
    // with the island (radius - padding); stretches while it flies.
    SpringColor {
        id: plateColor
        target: root.armed !== "" ? root.theme.accentRed : (root.theme.sessionPlate ?? "#242426")
        stiffness: 4
        damping: 0.7
    }
    Rectangle {
        id: plate
        // Liquid stretch along the flight (the OCR panel's deform).
        transform: VelocityDeform { item: plate }
        x: root.cfg.padding + root.selected * (root.cfg.buttonSize + root.cfg.spacing)
        Behavior on x { Spring {} }
        y: root.cfg.padding
        width: root.cfg.buttonSize
        height: root.cfg.buttonSize
        radius: Math.max(0, root.cfg.radius - root.cfg.padding)
        color: plateColor.value
        visible: root.actions.length > 0
    }

    Row {
        id: row
        x: root.cfg.padding
        y: root.cfg.padding
        spacing: root.cfg.spacing

        Repeater {
            model: root.actions
            delegate: SessionButton {
                required property string modelData
                required property int index
                theme: root.theme
                cfg: root.cfg
                glyph: SessionActions.of(modelData).glyph
                selected: root.selected === index
                armed: root.armed === modelData
                onHovered: root.selected = index
                onClicked: root.press(index)
            }
        }
    }
}
