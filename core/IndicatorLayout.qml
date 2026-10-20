import QtQuick
import "../components"
import "../indicators"

// Bar content: a single Row centered in the island, in order
// [ timer | music(+timer ring) | privacy | dictation | clock ]; an event's glyph / text
// are pinned to the island's left / right edges outside it (eventSide).
// Nothing in the row is pinned to
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
    required property var privacy
    required property var events
    required property var players
    required property var network
    required property var recorder
    required property var dictation
    required property var theme
    required property var countdown
    // Status drop (Island): a status's event shows its text right after
    // the glyph (left half) and the inline ring in the right end rounding
    // (`statusInset` = its room past edgePad, `statusTextGap` = glyph ->
    // text); the timer leaves the row / music cover for the drop.
    property var statuses: null
    property real statusInset: 0
    property real statusTextGap: 8
    property bool timerInDrop: false
    // Width the island adds outside this layout (fullscreen notification
    // ticker): taken out of the eviction budget.
    property real extraReserve: 0
    signal requestModule(string name, var payload)

    Registry { id: registry }

    readonly property var servicesBundle: ({
            audio: root.audio,
            privacy: root.privacy,
            events: root.events,
            players: root.players,
            network: root.network,
            recorder: root.recorder,
            dictation: root.dictation,
            theme: root.theme,
            countdown: root.countdown,
            statuses: root.statuses,
            timerInDrop: root.timerInDrop,
            cfg: root.cfg,
            islandHeight: root.islandHeight
        })

    // Visual order in the row; the timer ring is the leftmost (user), the
    // clock closes the row. An event's glyph / text take the far left / far
    // right of the island, outside the row.
    readonly property var orderedNames: ["timer", "music", "privacy", "dictation"]
    // Event halves sit OUTSIDE the row, pinned to the island edges (glyph
    // left, text right), and the island grows by the wider half on BOTH
    // sides — the row (and the clock) stays exactly centred on screen
    // (user: events must not push the main indicators).
    readonly property var eventNames: ["eventIcon", "eventText"]
    readonly property bool statusEvent: {
        const k = root.events?.current?.status ?? "";
        return k !== "" && !!root.statuses?.find(k);
    }
    readonly property real iconGlyphEnd: eventIconLoader.item?.glyphEnd ?? 0
    readonly property real eventSide: !root.indicatorActive("eventIcon") ? 0
        : root.statusEvent
        ? Math.max(root.iconGlyphEnd + root.statusTextGap + root.desiredWidth("eventText"), root.statusInset + (root.cfg.eventGap ?? 28))
        : Math.max(root.desiredWidth("eventIcon"), root.desiredWidth("eventText"))
    readonly property var loaders: ({
            eventIcon: eventIconLoader,
            privacy: privacyLoader,
            music: musicLoader,
            dictation: waveLoader,
            timer: timerLoader,
            eventText: eventTextLoader
        })

    // Live clock width (plate grows with the recording timer text).
    readonly property real clockWidth: clockPlate.implicitWidth
    // Clock as a shared-element owner (null while the recording/hotspot
    // plate replaces the clock face).
    readonly property Item clockOwner: clockPlate.active ? null : clockPlate
    // Timer ring as a shared-element owner (null while not loaded): around
    // the music cover while a player shows, else the stand-alone ring.
    // One music+timer indicator (Music.qml) when musicTimerRing is on.
    readonly property bool timerOnCover: !root.timerInDrop && (root.cfg.musicTimerRing ?? true)
    readonly property Item timerOwner: root.timerOnCover ? (musicLoader.item?.halo ?? null) : (timerLoader.item?.halo ?? null)
    // Clock centre in this item's coords (follows the row's springs).
    readonly property real clockCenterX: barRow.x + clockPlate.x + clockPlate.width / 2
    // Animated indicator widths (0 while hidden/evicted).
    readonly property real indicatorsNow: (privacyLoader.item?.width ?? 0)
        + (musicLoader.item?.width ?? 0)
        + (waveLoader.item?.width ?? 0)
        + (timerLoader.item?.width ?? 0)
    // Live content width: spacing/padding factors stay relative to the actual
    // current content size (spec), never to the island width (that would loop).
    // Deliberately excludes Row spacing so spacing never feeds back into itself.
    readonly property real contentNow: indicatorsNow + clockWidth
    readonly property real spacing: Math.max(4, contentNow * cfg.indicatorSpacingFactor)
    readonly property real edgePad: Math.max(cfg.edgePaddingMin ?? 16, contentNow * cfg.edgePaddingFactor)

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

    // Minimal → bar peek (core/IndicatorPeek): while `holdNew` only the
    // `known` names show — a newcomer waits until the bar has unfolded.
    property bool holdNew: false
    property var known: ({})
    // Active names for the peek's newcomer check (both event halves = "event").
    readonly property string activeKey: orderedNames.concat(["event"]).filter(n => root.rawActive(n)).join(",")

    function indicatorActive(name: string): bool {
        if (!root.rawActive(name))
            return false;
        const key = name === "eventIcon" || name === "eventText" ? "event" : name;
        return !root.holdNew || !!root.known[key];
    }

    function rawActive(name: string): bool {
        if (name === "event" || name === "eventIcon" || name === "eventText")
            return root.events.current !== null;
        if (name === "privacy")
            return root.privacy.active;
        if (name === "music")
            return root.players.musicActive || (root.timerOnCover && (root.countdown?.active ?? false));
        if (name === "dictation")
            return root.dictation.active && root.dictation.sink === "type";
        if (name === "timer")
            return (root.countdown?.active ?? false) && !root.timerOnCover && !root.timerInDrop;
        return false;
    }

    function desiredWidth(name: string): real {
        return root.loaders[name]?.item?.desiredWidth ?? 0;
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
    readonly property real edgePadD: Math.max(cfg.edgePaddingMin ?? 16, desiredContent * cfg.edgePaddingFactor)

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
        const budget = root.islandCfg.maxWidth - root.edgePadD * 2 - root.clockWidth - root.eventSide * 2 - root.extraReserve;
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
    readonly property var loaderState: {
        const out = {};
        for (const n of [...root.orderedNames, ...root.eventNames]) {
            const l = root.loaders[n];
            out[n] = [l.active, l.item !== null, l.item?.width ?? -1];
        }
        return out;
    }

    // Order: [ timer | music(+timer ring) | privacy | dictation | clock ].
    // Every child is vertically centered (pShell pattern): without it, Row
    // top-aligns children and short ones (the 8px mic dot next to the 24px
    // music cover) stick to the top edge.
    // While an event shows, the row recedes (user: the clock and the other
    // indicators clashed with it): fades to `eventRowOpacity` under a light
    // content blur (`eventRowBlur`). Queued events keep it dimmed through
    // the collapse gap between them, so it never flickers bright.
    readonly property bool eventShowing: (!root.holdNew || !!root.known["event"]) && ((root.events?.current ?? null) !== null
        || (root.events?.queue?.length ?? 0) > 0)
    property real rowDim: root.eventShowing ? 1 : 0
    Behavior on rowDim { Spring { stiffness: 4; damp: 0.5; eps: 0.005 } }

    BlurSurface {
        id: rowSurface
        anchors.fill: parent
        amount: root.rowDim * (root.cfg?.eventRowBlur ?? 0.3)
        opacity: 1 - root.rowDim * (1 - (root.cfg?.eventRowOpacity ?? 0.45))

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
                    item.requestOpen.connect((n, p) => root.requestModule(n, p));
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
                id: privacyLoader
                anchors.verticalCenter: parent.verticalCenter
                Behavior on x { Spring {} }
                width: item ? item.width : 0
                height: item ? item.height : 0
                // Unload only after the item has collapsed (width glides down
                // via its own spring while still loaded, in sync with the
                // island — same Spring, same frame). Unloading instantly would
                // snap the row and teleport the clock.
                readonly property bool collapsing: item !== null && !root.indicatorActive("privacy") && item.width > 0.5
                sourceComponent: registry.privacyIndicator
                active: root.indicatorActive("privacy") || collapsing
                onLoaded: {
                    item.services = Qt.binding(() => root.servicesBundle);
                    item.evicted = Qt.binding(() => root.isEvicted("privacy"));
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

        }
    }

    // Event halves, pinned to the island edges (see eventSide).
    Loader {
        id: eventIconLoader
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: root.edgePadD
        width: item ? item.width : 0
        height: item ? item.height : 0
        readonly property bool collapsing: item !== null && !root.indicatorActive("eventIcon") && item.width > 0.5
        sourceComponent: registry.eventIconIndicator
        active: root.indicatorActive("eventIcon") || collapsing
        onLoaded: {
            item.services = Qt.binding(() => root.servicesBundle);
            item.evicted = false;
        }
    }
    Loader {
        id: eventTextLoader
        anchors.verticalCenter: parent.verticalCenter
        // Status event: right after the glyph; otherwise the far right.
        x: root.statusEvent ? root.edgePadD + root.iconGlyphEnd + root.statusTextGap
            : parent.width - root.edgePadD - width
        width: item ? item.width : 0
        height: item ? item.height : 0
        readonly property bool collapsing: item !== null && !root.indicatorActive("eventText") && item.width > 0.5
        sourceComponent: registry.eventTextIndicator
        active: root.indicatorActive("eventText") || collapsing
        onLoaded: {
            item.services = Qt.binding(() => root.servicesBundle);
            item.evicted = false;
            item.leading = Qt.binding(() => root.statusEvent);
        }
    }
    // Event `tap` (a function, e.g. open the drive just plugged in) or
    // `open` (an island module name, opened on THIS island): both halves
    // take the click — only while the visible event has one, so they never
    // swallow presses meant for the gesture layer otherwise.
    readonly property bool eventTappable: typeof root.events?.current?.tap === "function"
        || (root.events?.current?.open ?? "") !== ""
    function tapEvent(): void {
        const ev = root.events?.current;
        const tap = ev?.tap;
        const open = ev?.open ?? "";
        if (typeof tap !== "function" && open === "")
            return;
        root.events.finish();
        if (typeof tap === "function")
            tap();
        else
            root.requestModule(open, ev.openPayload ?? {});
    }
    MouseArea {
        x: eventIconLoader.x
        y: 0
        width: eventIconLoader.width
        height: parent.height
        enabled: root.eventTappable
        visible: enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.tapEvent()
    }
    MouseArea {
        x: eventTextLoader.x
        y: 0
        width: eventTextLoader.width
        height: parent.height
        enabled: root.eventTappable
        visible: enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.tapEvent()
    }
}
