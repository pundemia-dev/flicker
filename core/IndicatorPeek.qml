import QtQuick

// Minimal → bar peek for a NEW indicator (user, Oct 2026): any indicator that
// turns on while the island is Minimal (a row indicator, an event, a status's
// event) first unfolds the bar WITHOUT it, and only once the bar has settled
// (`peekRevealMs`) the newcomer appears in it. The bar stays `peekShowMs`
// (longer while an event shows or the bar is hovered), then folds back.
//
// While `holding` IndicatorLayout shows only the `known` names (snapshot of
// what was on when the hold began); a name absent from it is a newcomer.
Item {
    id: root
    property var cfg: null          // config.indicators
    property bool minimal: false    // island state is Minimal
    property bool revealed: false   // bar already shown by something else (ticker / hold reveal)
    property bool blocked: false    // module open, start-up, capture: no peek now
    property bool keepOpen: false   // event showing / bar hovered
    property string rawKey: ""      // IndicatorLayout.activeKey

    property var known: ({})
    property bool active: false     // the bar shape is drawn for the peek
    property bool ready: false      // bar settled: newcomers may show
    property bool waiting: false    // show time over, waiting for keepOpen to fall
    readonly property bool holding: root.minimal && !root.ready && !root.revealed

    function namesOf(key: string): var {
        return key === "" ? [] : key.split(",");
    }
    function setOf(names: var): var {
        const s = {};
        for (const n of names)
            s[n] = true;
        return s;
    }

    function sync(): void {
        if (!root.holding)
            return;
        const ignore = root.cfg?.peekIgnore ?? [];
        const k = {};
        let fresh = false;
        for (const n of root.namesOf(root.rawKey)) {
            if (root.known[n] || ignore.includes(n))
                k[n] = true;
            else
                fresh = true;
        }
        // Names that went off drop out: coming back later is new again.
        root.known = k;
        if (fresh && !root.blocked && !root.active && (root.cfg?.peekEnabled ?? true))
            root.start();
    }

    function start(): void {
        root.active = true;
        root.ready = false;
        root.waiting = false;
        revealTimer.restart();
    }
    function end(): void {
        revealTimer.stop();
        showTimer.stop();
        tailTimer.stop();
        root.waiting = false;
        root.ready = false;
        root.active = false;
    }

    onRawKeyChanged: root.sync()
    onBlockedChanged: {
        // Whatever came on meanwhile (start-up, under a module) counts as
        // known: it shows with the next bar, without a peek of its own.
        if (root.blocked)
            root.end();
        else if (root.holding)
            root.known = root.setOf(root.namesOf(root.rawKey));
    }
    // A new hold starts from what is on right now.
    onHoldingChanged: {
        if (root.holding)
            root.known = root.setOf(root.namesOf(root.rawKey));
    }
    onMinimalChanged: {
        if (!root.minimal)
            root.end();
    }
    onKeepOpenChanged: {
        if (!root.keepOpen && root.waiting)
            tailTimer.restart();
        else if (root.keepOpen)
            tailTimer.stop();
    }

    Timer {
        id: revealTimer
        interval: root.cfg?.peekRevealMs ?? 450
        onTriggered: {
            root.ready = true;
            showTimer.restart();
        }
    }
    Timer {
        id: showTimer
        interval: root.cfg?.peekShowMs ?? 3000
        onTriggered: {
            if (root.keepOpen)
                root.waiting = true;
            else
                root.end();
        }
    }
    Timer {
        id: tailTimer
        interval: root.cfg?.peekTailMs ?? 1000
        onTriggered: root.end()
    }
}
