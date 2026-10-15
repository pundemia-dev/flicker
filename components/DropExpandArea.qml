import QtQuick

// Trigger for a DropExpand: put it inside the button / card (anchors.fill)
// — a click or a long press opens `expander` from `source` (default: the
// parent) with `options` (DropExpand.open; may be a function returning
// them, evaluated at the trigger). mode "click" | "hold"; a click on an
// open one folds it back. In "hold" mode a plain click still emits
// `clicked` (the button's own action).
MouseArea {
    id: root
    property Item expander: null
    property Item source: root.parent
    property var options: ({})
    property string mode: "click"
    property int holdMs: 450

    pressAndHoldInterval: root.holdMs
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    property bool held: false
    function trigger(): void {
        const o = typeof root.options === "function" ? root.options() : root.options;
        root.expander?.toggle(root.source, o);
    }

    onPressed: root.held = false
    onPressAndHold: {
        if (root.mode !== "hold")
            return;
        root.held = true;
        root.trigger();
    }
    onClicked: mouse => {
        if (root.mode === "click")
            root.trigger();
        else if (root.held)
            mouse.accepted = true;
    }
}
