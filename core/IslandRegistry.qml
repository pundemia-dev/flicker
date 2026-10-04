import QtQuick

// Per-screen island instances (one per output). IPC routes through here to
// the island on the focused output, falling back to the first one.
QtObject {
    id: root
    property var islands: []

    function register(island: var): void {
        root.islands = [...root.islands, island];
    }

    function unregister(island: var): void {
        root.islands = root.islands.filter(i => i !== island);
    }

    function forOutput(name: string): var {
        return root.islands.find(i => i.screen?.name === name) ?? root.islands[0] ?? null;
    }
}
