import QtQuick
import Quickshell
import Quickshell.Io

// One JSON state file in Quickshell.statePath(name), read at creation
// (blockLoading: handle `onLoaded` and call read()). read() = the parsed
// object, {} when missing or unreadable (a bad file is logged and ignored);
// write(obj) stores obj with `version`. Callers validate the fields.
FileView {
    id: file
    required property string name
    property int version: 1

    path: Quickshell.statePath(file.name)
    blockLoading: true
    printErrors: false

    function read(): var {
        const t = file.text();
        if (!t)
            return {};
        try {
            const s = JSON.parse(t);
            return s && typeof s === "object" ? s : {};
        } catch (e) {
            console.warn(`StateFile: bad ${file.name}, ignoring:`, e);
            return {};
        }
    }
    function write(obj: var): void {
        file.setText(JSON.stringify(Object.assign({ version: file.version }, obj)));
    }
}
