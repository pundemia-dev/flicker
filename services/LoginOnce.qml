import QtQuick
import Quickshell
import Quickshell.Io

// A marker in $XDG_RUNTIME_DIR (gone at logout / reboot): claim() is true
// the first time per login and false after, hot reloads included. For
// start-up restores a reload must not repeat (it would undo changes made
// since, or restore a level saved before a debounce fired).
FileView {
    id: marker
    required property string name

    path: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/flicker-${marker.name}-restored`
    blockLoading: true
    printErrors: false

    function claim(): bool {
        if (marker.text() !== "")
            return false;
        marker.setText("1");
        return true;
    }
}
