import QtQuick

// Types a string into the focused window (launcher emoji plugin): the same
// wtype path as dictation (DictationTyper), own instance so it never touches
// a running dictation's typed-text state. Lives in Shell, not in the
// plugin: the launcher destroys its plugins on close, and the text has to
// go out AFTER the island let go of the keyboard (delayMs), when focus is
// back on the window.
Item {
    id: root

    property string _pending: ""

    function typeLater(text: string, delayMs: int): void {
        root._pending = text ?? "";
        if (root._pending === "")
            return;
        delay.interval = Math.max(0, delayMs);
        delay.restart();
    }

    Timer {
        id: delay
        onTriggered: {
            typer.reset();
            typer.applyText(root._pending);
        }
    }

    DictationTyper {
        id: typer
        onFailed: msg => console.warn("[TextTyper]", msg)
    }
}
