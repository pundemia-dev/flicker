import QtQuick
import "../../components"

// Drill-down navigation (iOS): pages are created on push and slide in from
// the right on a spring while the one below drifts left and dims; pop
// reverses it and destroys the page once it is off the card. Pages below
// keep their scroll position. A new section (rootPage) swaps the whole
// stack through the blur-fade (out, swap, in); `shown` = false (search)
// fades it away without a swap.
FadeBlur {
    id: root
    required property var host
    required property var theme
    property var rootPage: null

    property var pages: []
    property var shownRoot: null
    readonly property bool swapping: root.rootPage !== root.shownRoot
    property bool visibleWanted: true

    shown: root.visibleWanted && !root.swapping

    onRootPageChanged: if (root.p < 0.02) root.commit()
    onPChanged: if (root.swapping && root.p < 0.02) root.commit()
    Component.onCompleted: root.commit()

    function make(page: var, depth: int, slot: real): var {
        return pageComp.createObject(root, {
            page: page,
            depth: depth,
            backLabel: depth > 0 ? root.pages[root.pages.length - 1].page.title : "",
            slot: slot
        });
    }

    function commit(): void {
        for (const p of root.pages)
            p.destroy();
        root.pages = root.rootPage ? [root.make(root.rootPage, 0, 0)] : [];
        root.shownRoot = root.rootPage;
    }

    function push(page: var): void {
        const item = root.make(page, root.pages.length, 1);
        root.pages[root.pages.length - 1].slot = -1;
        root.pages = root.pages.concat([item]);
        Qt.callLater(() => item.slot = 0);
    }

    function pop(): bool {
        if (root.pages.length < 2)
            return false;
        const top = root.pages[root.pages.length - 1];
        root.pages = root.pages.slice(0, -1);
        root.pages[root.pages.length - 1].slot = 0;
        top.dying = true;
        top.slot = 1;
        return true;
    }

    function popToRoot(): void {
        while (root.pages.length > 2)
            root.pages.splice(-2, 1)[0].destroy();
        root.pop();
    }

    Component {
        id: pageComp
        SettingsPage {
            width: root.width
            height: root.height
            host: root.host
            theme: root.theme
        }
    }
}
