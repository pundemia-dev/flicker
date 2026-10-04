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

    // Back to the FRONT (a card displaced by user interaction during the
    // collapse gap keeps its place ahead of the rest).
    function requeue(item: var): void {
        root.items = [item, ...root.items];
    }

    // Drops an item wherever it is (the sender closed it while queued).
    function remove(item: var): void {
        root.items = root.items.filter(i => i !== item);
    }

    function clear(): void {
        root.items = [];
    }
}
