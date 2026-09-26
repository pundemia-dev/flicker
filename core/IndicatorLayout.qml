import QtQuick
import "../indicators"

// Row layout for background indicators, driven by indicators/Registry.qml
// (priorities). Left/right rows around the centered clock. The island fits
// its bar width to the measured content (see Island.barFittedWidth); when the
// desired content exceeds islandCfg.maxWidth, lower priority indicators are
// evicted first (fade + width collapse). Adding an indicator = QML file +
// Registry entry + one Loader below (same pattern as ModuleHost).
Item {
    id: root
    required property var cfg
    required property var islandCfg
    required property real clockWidth
    required property var audio
    required property var players
    required property var network
    required property var recorder
    required property var dictation
    required property var theme
    signal requestModule(string name, var payload)

    Registry { id: registry }

    readonly property var servicesBundle: ({
            audio: root.audio,
            players: root.players,
            network: root.network,
            recorder: root.recorder,
            dictation: root.dictation,
            theme: root.theme,
            cfg: root.cfg
        })

    // Measured (animated) row widths — the island fits itself to these.
    readonly property real leftContentWidth: leftRow.width
    readonly property real rightContentWidth: rightRow.width
    // Live content width: spacing/padding factors stay relative to the actual
    // current content size (spec), never to the island width (that would loop).
    readonly property real contentNow: leftContentWidth + rightContentWidth + clockWidth
    readonly property real spacing: Math.max(4, contentNow * cfg.indicatorSpacingFactor)
    readonly property real edgePad: Math.max(12, contentNow * cfg.edgePaddingFactor)

    readonly property var leftNames: {
        const list = [];
        for (const e of registry.entries)
            if (e.side === "left")
                list.push(e.name);
        return list;
    }
    readonly property var rightNames: {
        const list = [];
        for (const e of registry.entries)
            if (e.side === "right")
                list.push(e.name);
        return list;
    }

    function indicatorActive(name: string): bool {
        if (name === "microphone")
            return root.audio.micActive;
        if (name === "music")
            return root.players.musicActive;
        if (name === "dictation")
            return root.dictation.active;
        return false;
    }

    function desiredWidth(name: string): real {
        if (name === "microphone")
            return micLoader.item ? micLoader.item.desiredWidth : 0;
        if (name === "music")
            return musicLoader.item ? musicLoader.item.desiredWidth : 0;
        if (name === "dictation")
            return waveLoader.item ? waveLoader.item.desiredWidth : 0;
        if (name === "timer")
            return timerLoader.item ? timerLoader.item.desiredWidth : 0;
        return 0;
    }

    function priorityOf(name: string): int {
        for (const e of registry.entries)
            if (e.name === name)
                return e.priority;
        return 0;
    }

    // Stable (desired) widths for the eviction math. Never depend on
    // `evicted` or animated widths — otherwise hide->refit->unhide
    // would oscillate, and newcomers could deadlock against a grown island.
    readonly property real leftDesired: {
        let sum = 0;
        for (const n of leftNames)
            if (indicatorActive(n))
                sum += desiredWidth(n);
        return sum;
    }
    readonly property real rightDesired: {
        let sum = 0;
        for (const n of rightNames)
            if (indicatorActive(n))
                sum += desiredWidth(n);
        return sum;
    }
    readonly property real desiredContent: leftDesired + rightDesired + clockWidth
    readonly property real spacingD: Math.max(4, desiredContent * cfg.indicatorSpacingFactor)
    readonly property real edgePadD: Math.max(12, desiredContent * cfg.edgePaddingFactor)
    // Eviction budget from the island cap: while the desired content fits
    // under maxWidth, nothing is evicted and the island grows to fit it.
    readonly property real evictBudget: islandCfg.maxWidth / 2 - clockWidth / 2 - edgePadD

    // Eviction: keep the highest-priority indicators that fit the budget;
    // the top-priority one is always kept.
    function evictedNamesFor(names: var): var {
        const active = [];
        for (const n of names) {
            if (!indicatorActive(n))
                continue;
            active.push({ name: n, priority: priorityOf(n), width: desiredWidth(n) });
        }
        active.sort((a, b) => b.priority - a.priority);
        const evicted = [];
        let used = 0;
        for (let i = 0; i < active.length; i++) {
            const need = (used > 0 ? root.spacingD : 0) + active[i].width;
            if (i === 0 || used + need <= root.evictBudget)
                used += need;
            else
                evicted.push(active[i].name);
        }
        return evicted;
    }

    readonly property var evictedNames: [...evictedNamesFor(leftNames), ...evictedNamesFor(rightNames)]

    function isEvicted(name: string): bool {
        return evictedNames.indexOf(name) !== -1;
    }

    // Order per spec: [ microphone | music | dictation | time | ... ]
    Row {
        id: leftRow
        spacing: root.spacing
        anchors.left: parent.left
        anchors.leftMargin: root.edgePad
        anchors.verticalCenter: parent.verticalCenter

        Loader {
            id: micLoader
            sourceComponent: registry.microphoneIndicator
            active: root.indicatorActive("microphone")
            onLoaded: {
                item.services = Qt.binding(() => root.servicesBundle);
                item.evicted = Qt.binding(() => root.isEvicted("microphone"));
            }
        }
        Loader {
            id: musicLoader
            sourceComponent: registry.musicIndicator
            active: root.indicatorActive("music")
            onLoaded: {
                item.services = Qt.binding(() => root.servicesBundle);
                item.evicted = Qt.binding(() => root.isEvicted("music"));
                if (item.requestOpen)
                    item.requestOpen.connect((n, p) => root.requestModule(n, p));
            }
        }
        Loader {
            id: waveLoader
            sourceComponent: registry.dictationIndicator
            active: root.indicatorActive("dictation")
            onLoaded: {
                item.services = Qt.binding(() => root.servicesBundle);
                item.evicted = Qt.binding(() => root.isEvicted("dictation"));
            }
        }
    }

    // Right side per spec: recording / timer / hotspot. Recording and hotspot
    // are rendered on the clock plate (see ClockPlate.qml); the row stays for
    // future Registry-driven indicators (timer, etc.).
    Row {
        id: rightRow
        spacing: root.spacing
        anchors.right: parent.right
        anchors.rightMargin: root.edgePad
        anchors.verticalCenter: parent.verticalCenter

        Loader {
            id: timerLoader
            sourceComponent: registry.timerIndicator
            active: root.indicatorActive("timer")
            onLoaded: {
                item.services = Qt.binding(() => root.servicesBundle);
                item.evicted = Qt.binding(() => root.isEvicted("timer"));
            }
        }
    }
}
