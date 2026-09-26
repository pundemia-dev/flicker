import QtQuick
import "../components"
import "../indicators"

// Bar content: a single Row centered in the island, in spec order
// [ microphone | music | dictation | clock | timer ]. Nothing is pinned to
// the island edges, so the clock shifts whenever an indicator grows (e.g.
// the mic hover label) — the whole group stays centered and the island fits
// it (see Island.barFittedWidth). Recording/hotspot render on the clock
// plate itself (see ClockPlate.qml). When the desired content exceeds
// islandCfg.maxWidth, lower priority indicators are evicted first (fade +
// width collapse). Adding an indicator = QML file + Registry entry + one
// Loader below (same pattern as ModuleHost).
Item {
    id: root
    required property var cfg
    required property var islandCfg
    required property var clock
    required property real islandHeight
    required property var timingCfg
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

    // Visual order in the row (spec example); the clock sits between the
    // left indicators and the timer.
    readonly property var orderedNames: ["microphone", "music", "dictation", "timer"]

    // Live clock width (plate grows with the recording timer text).
    readonly property real clockWidth: clockPlate.implicitWidth
    // Animated indicator widths (0 while hidden/evicted).
    readonly property real indicatorsNow: (micLoader.item?.width ?? 0)
        + (musicLoader.item?.width ?? 0)
        + (waveLoader.item?.width ?? 0)
        + (timerLoader.item?.width ?? 0)
    // Live content width: spacing/padding factors stay relative to the actual
    // current content size (spec), never to the island width (that would loop).
    // Deliberately excludes Row spacing so spacing never feeds back into itself.
    readonly property real contentNow: indicatorsNow + clockWidth
    readonly property real spacing: Math.max(4, contentNow * cfg.indicatorSpacingFactor)
    readonly property real edgePad: Math.max(12, contentNow * cfg.edgePaddingFactor)

    // Measured row width (includes inter-item spacing).
    readonly property real barRowWidth: barRow.width

    // Stable row width: the island's width target. Built ONLY from stable
    // (desired) widths, never from animated ones — so on hover the island
    // target jumps in one step and its spring runs the SAME curve as the
    // indicator's own width spring (identical Spring params, same frame):
    // siblings, not series. Series (island target following the animated
    // row) expands in two visible stages; a snapped row teleports the clock.
    // Every kept indicator costs its width plus one gap (each is always
    // adjacent to the clock or another indicator).
    readonly property real keptSum: {
        let sum = 0;
        for (const n of orderedNames)
            if (indicatorActive(n) && !isEvicted(n))
                sum += desiredWidth(n);
        return sum;
    }
    readonly property int keptCount: {
        let c = 0;
        for (const n of orderedNames)
            if (indicatorActive(n) && !isEvicted(n))
                c++;
        return c;
    }
    readonly property real stableRowWidth: keptSum + clockWidth + spacingD * keptCount

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
    readonly property real indicatorsDesired: {
        let sum = 0;
        for (const n of orderedNames)
            if (indicatorActive(n))
                sum += desiredWidth(n);
        return sum;
    }
    readonly property real desiredContent: indicatorsDesired + clockWidth
    readonly property real spacingD: Math.max(4, desiredContent * cfg.indicatorSpacingFactor)
    readonly property real edgePadD: Math.max(12, desiredContent * cfg.edgePaddingFactor)

    // Eviction against the single shared budget: the whole centered row must
    // fit under maxWidth. Each kept indicator costs its width plus one gap.
    // Highest priority first; the top-priority one is always kept.
    readonly property var evictedNames: {
        const active = [];
        for (const n of orderedNames) {
            if (!indicatorActive(n))
                continue;
            active.push({ name: n, priority: priorityOf(n), width: desiredWidth(n) });
        }
        active.sort((a, b) => b.priority - a.priority);
        const budget = root.islandCfg.maxWidth - root.edgePadD * 2 - root.clockWidth;
        const evicted = [];
        let used = 0;
        for (let i = 0; i < active.length; i++) {
            // Every kept indicator adds one gap (always adjacent to the clock
            // or another indicator) — same accounting as stableRowWidth.
            const need = active[i].width + root.spacingD;
            if (i === 0 || used + need <= budget)
                used += need;
            else
                evicted.push(active[i].name);
        }
        return evicted;
    }

    function isEvicted(name: string): bool {
        return evictedNames.indexOf(name) !== -1;
    }

    // Loader introspection (debugState): catches ghost items (loaded but
    // invisible) keeping the row wide after the indicator is gone.
    readonly property var loaderState: ({
            microphone: [micLoader.active, micLoader.item !== null, micLoader.item?.width ?? -1],
            music: [musicLoader.active, musicLoader.item !== null, musicLoader.item?.width ?? -1],
            dictation: [waveLoader.active, waveLoader.item !== null, waveLoader.item?.width ?? -1],
            timer: [timerLoader.active, timerLoader.item !== null, timerLoader.item?.width ?? -1]
        })

    // Order per spec: [ microphone | music | dictation | clock | timer ].
    // Every child is vertically centered (pShell pattern): without it, Row
    // top-aligns children and short ones (the 8px mic dot next to the 24px
    // music cover) stick to the top edge.
    Row {
        id: barRow
        anchors.centerIn: parent
        // Stable spacing: the row width must glide on the same curve as the
        // island (see stableRowWidth), so gaps can't be driven by animated
        // widths mid-morph.
        spacing: root.spacingD

        // Explicit geometry from the loaded item (0 when unloaded):
        // QQuickLoader keeps its last size after unloading, so without this
        // a dead 8px mic Loader keeps the row (and the island's padding)
        // wide forever. No width spring here: the loader must track the
        // item's own (spring-animated) width exactly — its own spring would
        // lag behind, leaving the full-width text hanging over the clock.
        // Smooth collapse on unload comes from delayed unload below: the
        // item stays loaded while its width spring shrinks to ~0.
        // Spring on movement: Row sets x from the (springing) widths, so each
        // child glides to its slot instead of jumping with the layout.
        Loader {
            id: micLoader
            anchors.verticalCenter: parent.verticalCenter
            Behavior on x { Spring {} }
            width: item ? item.width : 0
            height: item ? item.height : 0
            // Unload only after the item has collapsed (width glides down
            // via its own spring while still loaded, in sync with the
            // island — same Spring, same frame). Unloading instantly would
            // snap the row and teleport the clock.
            readonly property bool collapsing: item !== null && !root.indicatorActive("microphone") && item.width > 0.5
            sourceComponent: registry.microphoneIndicator
            active: root.indicatorActive("microphone") || collapsing
            onLoaded: {
                item.services = Qt.binding(() => root.servicesBundle);
                item.evicted = Qt.binding(() => root.isEvicted("microphone"));
            }
        }
        Loader {
            id: musicLoader
            anchors.verticalCenter: parent.verticalCenter
            Behavior on x { Spring {} }
            width: item ? item.width : 0
            height: item ? item.height : 0
            readonly property bool collapsing: item !== null && !root.indicatorActive("music") && item.width > 0.5
            sourceComponent: registry.musicIndicator
            active: root.indicatorActive("music") || collapsing
            onLoaded: {
                item.services = Qt.binding(() => root.servicesBundle);
                item.evicted = Qt.binding(() => root.isEvicted("music"));
                if (item.requestOpen)
                    item.requestOpen.connect((n, p) => root.requestModule(n, p));
            }
        }
        Loader {
            id: waveLoader
            anchors.verticalCenter: parent.verticalCenter
            Behavior on x { Spring {} }
            width: item ? item.width : 0
            height: item ? item.height : 0
            readonly property bool collapsing: item !== null && !root.indicatorActive("dictation") && item.width > 0.5
            sourceComponent: registry.dictationIndicator
            active: root.indicatorActive("dictation") || collapsing
            onLoaded: {
                item.services = Qt.binding(() => root.servicesBundle);
                item.evicted = Qt.binding(() => root.isEvicted("dictation"));
            }
        }

        ClockPlate {
            id: clockPlate
            anchors.verticalCenter: parent.verticalCenter
            Behavior on x { Spring {} }
            clock: root.clock
            recorder: root.recorder
            network: root.network
            theme: root.theme
            islandHeight: root.islandHeight
            cfg: root.cfg
            timingCfg: root.timingCfg
            onRequestModule: name => root.requestModule(name, {})
        }

        Loader {
            id: timerLoader
            anchors.verticalCenter: parent.verticalCenter
            Behavior on x { Spring {} }
            width: item ? item.width : 0
            height: item ? item.height : 0
            readonly property bool collapsing: item !== null && !root.indicatorActive("timer") && item.width > 0.5
            sourceComponent: registry.timerIndicator
            active: root.indicatorActive("timer") || collapsing
            onLoaded: {
                item.services = Qt.binding(() => root.servicesBundle);
                item.evicted = Qt.binding(() => root.isEvicted("timer"));
            }
        }
    }
}
