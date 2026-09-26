import QtQuick

QtObject {
    id: root
    property var items: []
    readonly property int size: items.length

    function enqueue(item: var): void {
        root.items = [...root.items, item];
    }

    function dequeue(): var {
        if (root.items.length === 0)
            return null;
        const head = root.items[0];
        root.items = root.items.slice(1);
        return head;
    }

    function clear(): void {
        root.items = [];
    }
}
