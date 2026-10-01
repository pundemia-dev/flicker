import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../components"

PanelWindow {
    id: root
    required property ShellScreen screen
    required property var config
    required property var theme
    required property var compositor
    required property var clock
    required property var audio
    required property var players
    required property var network
    required property var bluetooth
    required property var battery
    required property var brightness
    required property var notifications
    required property var recorder
    required property var dictation
    required property var systemUsage
    required property var weather
    required property var lock

    screen: root.screen
    color: "transparent"
    visible: !root.lock.locked
    // Overlay (not Top): niri does not composite Top-layer surfaces above a
    // fullscreen window, but Overlay stays visible. The spec requires the
    // island (minimal strip, tickers, modules opened from minimal) to work
    // during fullscreen, so the island lives on Overlay.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.state.activeModule === "launcher" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    anchors.top: true
    anchors.left: true
    anchors.right: true
    // Input mask = island background + side gesture strips: clicks anywhere
    // else fall through to windows below. Without this the full-width layer
    // surface (tight but still screen-wide) swallows the whole top strip.
    // The side strips (100x5 at the top edge, adjacent to the island) are
    // the QS / Notification Center drag handles from GestureZones.detectZone;
    // they stay out of the mask while a module is open (a press there could
    // never open anything then — moduleSwipe takes over — so keeping them
    // would just eat window clicks). Gestures that start inside the mask
    // keep tracking outside via the press grab, so dashboard/presentation/
    // swipe-up drags still work; presses that start outside never reach us.
    mask: Region {
        x: Math.round(root.islandX)
        y: Math.round(root.islandY)
        width: Math.round(root.islandWidth)
        height: Math.round(root.islandHeight)

        Region {
            x: Math.round(root.islandX - root.gestureCfg.notificationsZoneWidth)
            y: 0
            width: root.moduleOpen ? 0 : Math.round(root.gestureCfg.notificationsZoneWidth)
            height: Math.round(root.gestureCfg.notificationsZoneHeight)
        }
        Region {
            x: Math.round(root.islandX + root.islandWidth)
            y: 0
            width: root.moduleOpen ? 0 : Math.round(root.gestureCfg.quickSettingsZoneWidth)
            height: Math.round(root.gestureCfg.quickSettingsZoneHeight)
        }
    }
    // The layer surface stays tight around the island (plus arcs overhang
    // and the minimal active zone) purely to keep the window small; input
    // is gated by the mask above, so surface size alone never blocks clicks.
    // In the bar state the side arcs stick out past the island (concentric
    // with the end roundings), so the surface also covers their overhang.
    readonly property real arcsBottom: root.islandY + root.islandHeight / 2 + arcsShape.extent + 1
    implicitHeight: Math.max(root.islandY + root.islandHeight + 8,
        (root.shouldDrawIslandShape && !root.moduleOpen) ? root.arcsBottom : 0,
        root.haloVisible ? root.islandY + root.islandHeight + root.haloPad + 1 : 0,
        gestureCfg.minimalActiveZoneHeight + 8)

    property IslandState state: IslandState {}
    property NotificationQueue notificationQueue: NotificationQueue {}
    // Minimal-hold reveal (press the active zone to peek at the bar).
    property bool temporaryRevealFromMinimal: false
    property bool holdRevealing: false
    property bool tickerVisible: false
    property string tickerText: ""
    // Dashboard drawer: island height follows the cursor while dragging from
    // the clock, snapping open past dashboardDragThreshold (spec).
    property bool dashboardDragging: false
    property real dashboardPreviewDy: 0
    // appearFromEdge primitive: the Minimal strip slides in from the top
    // edge at startup, then morphs into the bar (see startupMorph timer).
    property bool started: false

    readonly property var islandCfg: config.island
    readonly property var timingCfg: config.timings
    readonly property var gestureCfg: config.gestures
    readonly property var indicatorCfg: config.indicators

    readonly property bool minimal: state.currentState === state.minimal
    readonly property bool moduleOpen: state.currentState === state.module
    readonly property bool showBarContent: !moduleOpen
    // Per-screen compositor state (global value as fallback).
    readonly property var screenInfo: (compositor?.perScreen ?? {})[screen.name] ?? null
    readonly property bool fsActive: screenInfo ? (screenInfo.fullscreen ?? false) : (compositor?.fullscreen ?? false)
    // Identifies the current island content; changing it replays the
    // ContentSwap blur->fade transition (openCount makes re-opens of the
    // same module - e.g. queued notifications - replay the swap too).
    readonly property string contentKey: root.moduleOpen
        ? `module:${root.state.activeModule}:${root.state.openCount}`
        : (root.tickerVisible ? "ticker" : "bar")
    readonly property bool shouldDrawIslandShape: !minimal || temporaryRevealFromMinimal || tickerVisible

    // Module size from config.modules (key "notifications:flow"/"notifications:center"
    // splits the notifications module by payload mode); island.moduleWidth/Height
    // is the fallback for unlisted names. Every module island is sized apart.
    readonly property string moduleKey: {
        if (root.state.activeModule === "notifications") {
            const mode = root.state.activePayload?.mode ?? "";
            if (mode !== "")
                return `notifications:${mode}`;
        }
        return root.state.activeModule;
    }
    readonly property var moduleSize: {
        const all = root.config.modules ?? {};
        return all[root.moduleKey] ?? all[root.state.activeModule]
            ?? ({ width: root.islandCfg.moduleWidth, height: root.islandCfg.moduleHeight });
    }

    // Bar width fits the content (spec: no fixed bar width): a single Row
    // centered in the island (indicators + clock in spec order, nothing
    // pinned to the edges), so the clock shifts when an indicator grows
    // (e.g. the mic hover label). Follows the STABLE row target
    // (IndicatorLayout.stableRowWidth): the island spring then runs the same
    // curve as the indicator width springs — one synchronized motion, the
    // clock glides instead of teleporting. Capped at islandCfg.maxWidth
    // (eviction in IndicatorLayout kicks in past the cap).
    readonly property real barFittedWidth: indicators.edgePadD * 2 + indicators.stableRowWidth

    readonly property real islandWidth: root.moduleOpen
        ? root.moduleSize.width
        : (root.shouldDrawIslandShape ? Math.min(root.barFittedWidth, root.islandCfg.maxWidth) : root.islandCfg.minimalWidth)
    readonly property real islandHeight: root.moduleOpen
        ? (root.dashboardDragging ? Math.min(root.moduleSize.height, root.islandCfg.height + root.dashboardPreviewDy) : root.moduleSize.height)
        : (root.shouldDrawIslandShape ? root.islandCfg.height : root.islandCfg.minimalHeight)
    readonly property real islandRadius: shouldDrawIslandShape ? islandCfg.radius : islandCfg.minimalRadius
    readonly property real islandX: (width - islandWidth) / 2
    readonly property real islandY: started ? islandCfg.topMargin : -(islandCfg.height + islandCfg.topMargin)

    // appearFromEdge (spec): the shell appears as the Minimal strip sliding
    // in from the top edge, then morphs into the bar on its spot. Starting
    // in Minimal (not Island) is what makes the first phase a thin strip.
    Component.onCompleted: {
        state.setMinimal();
        startupTimer.start();
    }

    // Real backdrop blur via niri's ext-background-effect-v1 (pShell pattern):
    // the island rect is published as the compositor blur region. Two region
    // objects alternate (ping-pong): re-assigning the SAME object is a no-op
    // for the compositor, so every kick must present a different object;
    // assigning null clears the effect. Visible behind translucent island areas.
    //
    // Live tracking: the region follows the island THROUGH morphs (every
    // geometry/state change re-kicks with the current int-snapped shape),
    // so the blur resizes together with the background instead of blinking
    // out and back. The region is committed atomically with the surface, so
    // it cannot lag a frame behind. Kicks are throttled (leading edge +
    // trailing exact kick): recommitting + reallocating the effect buffers
    // every frame stutters big morphs like bar->module, so intermediates go
    // at most every blurKickIntervalMs while the final shape always lands
    // exact via the trailing timer.
    //
    // Pixel-exactness note: quickshell bakes Region radius into wl_region
    // as an integer QRegion-ellipse staircase and niri blurs exactly that
    // shape (layer surface, no layer-rule -> xray path, clip None,
    // radius 0), so the hard mask diverges ~1px from the smooth painted
    // corner. Per the DMS approach the region stays exact-fit and the
    // divergence zone is masked by the 1px island rim (see islandRect
    // border) instead of an inset.
    property bool blurAlt: false
    property string blurGeo: ""
    property double blurLastKickMs: 0
    readonly property int blurBaseX: Math.round(islandRect.x)
    readonly property int blurBaseY: Math.round(islandRect.y)
    readonly property int blurBaseW: Math.round(islandRect.width)
    readonly property int blurBaseH: Math.round(islandRect.height)
    readonly property int blurBaseR: Math.round(islandRect.radius)
    // DMS approach: the region is always exact-fit (no inset) and the
    // paint/blur boundary is masked by a 1px rim over the island edge
    // (see islandRect border) instead. Geometry stays int-snapped.

    function updateIslandBlur(): void {
        if (root.config.effects.disableBlur || root.config.effects.disableCompositorBlur) {
            blurKickTrail.stop();
            root.BackgroundEffect.blurRegion = null;
            root.blurGeo = "";
            return;
        }
        const g = `${root.blurBaseX},${root.blurBaseY},${root.blurBaseW},${root.blurBaseH},${root.blurBaseR}`;
        if (g === root.blurGeo)
            return;
        const now = Date.now();
        if (now - root.blurLastKickMs < root.timingCfg.blurKickIntervalMs) {
            // Morph in progress: defer, the trailing timer lands the latest
            // shape. Keeps per-frame effect reallocs from stuttering.
            blurKickTrail.restart();
            return;
        }
        root.blurLastKickMs = now;
        root.blurGeo = g;
        root.blurAlt = !root.blurAlt;
        root.BackgroundEffect.blurRegion = root.blurAlt ? islandBlurRegionA : islandBlurRegionB;
    }

    onFsActiveChanged: {
        if (root.moduleOpen)
            return;
        if (root.fsActive)
            root.state.setMinimal();
        else if (!root.tickerVisible && !root.temporaryRevealFromMinimal)
            root.state.setIsland();
    }

    function openModule(name: string, payload: var): void {
        state.openModule(name, payload);
        // Modules opened from Minimal return there after the idle timeout.
        if (state.currentState === state.module && state.previousState === state.minimal)
            moduleIdle.restart();
        else
            moduleIdle.stop();
    }

    function openLauncher(): void {
        openModule("launcher", {});
    }

    function openQuickSettings(): void {
        openModule("quicksettings", {});
    }

    function openCapture(): void {
        openModule("capture", {});
    }

    function openLock(): void {
        root.lock.activate();
    }

    function openNotificationCenter(): void {
        openModule("notifications", { mode: "center" });
    }

    function showOsd(title: string, icon: string, value: real): void {
        openModule("osd", {
                title: title,
                icon: icon,
                value: Math.max(0, Math.min(1, value))
            });
        osdAutoClose.restart();
    }

    function closeModule(): void {
        moduleIdle.stop();
        state.closeModule();
        if (notificationQueue.size > 0) {
            const next = notificationQueue.dequeue();
            openModule("notifications", { notification: next, mode: "flow" });
        }
    }

    function showTicker(notif: var): void {
        tickerText = `${notif.appName}: ${notif.summary}`;
        tickerVisible = true;
        tickerTimer.restart();
    }

    Connections {
        target: root.notifications
        function onNotificationReceived(notif) {
            const urgency = notif?.urgency ?? 1;
            if (root.config.notifications.onlyUrgentToast && urgency < 1)
                return;
            if (root.moduleOpen) {
                root.notificationQueue.enqueue(notif);
                return;
            }
            if (root.state.currentState === root.state.minimal || root.fsActive) {
                root.showTicker(notif);
            } else {
                root.openModule("notifications", { notification: notif, mode: "flow" });
            }
        }
    }

    Timer {
        id: tickerTimer
        interval: root.config.notifications.tickerDurationMs
        onTriggered: {
            root.tickerVisible = false;
            // The ticker itself counts as interaction: restart the idle timer.
            if (root.state.currentState === root.state.minimal)
                minimalIdle.restart();
        }
    }

    Timer {
        id: minimalIdle
        interval: root.timingCfg.minimalIdleMs
        onTriggered: {
            if (root.state.currentState === root.state.minimal && !root.fsActive)
                root.state.setIsland();
        }
    }

    Timer {
        id: moduleIdle
        interval: root.timingCfg.moduleIdleFromMinimalMs
        onTriggered: {
            if (root.state.currentState === root.state.module && root.state.previousState === root.state.minimal)
                root.closeModule();
        }
    }

    Timer {
        id: osdAutoClose
        interval: root.timingCfg.osdAutoCloseMs
        onTriggered: if (root.state.activeModule === "osd")
            root.closeModule()
    }

    Timer {
        id: startupTimer
        interval: root.timingCfg.startupDelayMs
        onTriggered: {
            root.started = true;
            root.updateIslandBlur();
            // Second phase of appearFromEdge: morph the Minimal strip into
            // the bar. Fires while the strip is still sliding so the morph
            // starts just short of the final position (tune via
            // timings.startupMorphDelayMs); the springs blend both motions.
            startupMorph.restart();
        }
    }

    Timer {
        id: startupMorph
        interval: root.timingCfg.startupMorphDelayMs
        onTriggered: {
            // Skipped under fullscreen (stays Minimal; onFsActiveChanged
            // brings the bar back later) and if the state already moved on
            // (e.g. a module opened in the meantime).
            if (!root.fsActive && root.state.currentState === root.state.minimal)
                root.state.setIsland();
        }
    }

    // Blur-region refresh triggers: state transitions + every island
    // geometry step re-kick live (see live-tracking note above). Identical
    // int-snapped geos dedupe inside updateIslandBlur, so per-frame calls
    // are free. The heartbeat is a safety net (e.g. for the disableBlur /
    // disableCompositorBlur config toggles, which have no change signal
    // on the nested JsonAdapter object).
    Connections {
        target: root.state
        function onCurrentStateChanged(): void { root.updateIslandBlur(); }
        function onActiveModuleChanged(): void { root.updateIslandBlur(); }
    }

    Connections {
        target: islandRect
        function onXChanged(): void { root.updateIslandBlur(); }
        function onYChanged(): void { root.updateIslandBlur(); }
        function onWidthChanged(): void { root.updateIslandBlur(); }
        function onHeightChanged(): void { root.updateIslandBlur(); }
        function onRadiusChanged(): void { root.updateIslandBlur(); }
    }

    Timer {
        id: blurHeartbeat
        interval: 2000
        repeat: true
        running: true
        onTriggered: root.updateIslandBlur()
    }

    // Trailing exact kick: fires blurKickIntervalMs after the last deferred
    // geometry step, so the settled shape always lands pixel-exact.
    Timer {
        id: blurKickTrail
        interval: root.timingCfg.blurKickIntervalMs
        onTriggered: root.updateIslandBlur()
    }

    // Compositor blur regions (ping-pong pair): the island rounded rect,
    // exact-fit, in surface-local int coords. Both track the live geometry;
    // kicks alternate.
    Region {
        id: islandBlurRegionA
        x: root.blurBaseX
        y: root.blurBaseY
        width: root.blurBaseW
        height: root.blurBaseH
        radius: root.blurBaseR
    }
    Region {
        id: islandBlurRegionB
        x: root.blurBaseX
        y: root.blurBaseY
        width: root.blurBaseW
        height: root.blurBaseH
        radius: root.blurBaseR
    }

    Arcs {
        id: arcsShape
        anchors.fill: islandRect
        z: -1
        network: root.network
        battery: root.battery
        islandRadius: root.islandRadius
        theme: root.theme
        cfg: root.config.arcs
        batteryCfg: root.config.battery
        visibleInState: root.state.currentState === root.state.island && !root.moduleOpen && !root.tickerVisible
    }

    // Light halo around the island body (the arcs' halo treatment, but
    // light): three nested border rings with falling opacity, so there is
    // no hard outer edge. Fully declarative — the rings follow the island
    // springs (width/height/radius/y) exactly with no repaints. Hidden
    // while Minimal (a glow around the 6px strip would dominate it).
    readonly property bool haloVisible: root.shouldDrawIslandShape || root.moduleOpen
    readonly property real haloW: root.islandCfg.haloWidth ?? 2
    readonly property real haloBorderW: root.islandCfg.haloBorder ?? 2
    readonly property real haloPeakA: (root.theme.islandHalo && root.theme.islandHalo.a !== undefined) ? root.theme.islandHalo.a : 0.004
    // Widest ring extent: keeps the layer surface tall enough (see
    // implicitHeight). The top sits tight against topMargin by design.
    readonly property real haloPad: root.haloW + root.haloBorderW

    Rectangle {
        color: "transparent"
        z: -1
        anchors.horizontalCenter: parent.horizontalCenter
        y: islandRect.y - root.haloW * 0.35
        width: islandRect.width + root.haloW * 0.7
        height: islandRect.height + root.haloW * 0.7
        radius: islandRect.radius + root.haloW * 0.35
        border.width: root.haloBorderW
        border.color: Qt.rgba(1, 1, 1, root.haloPeakA)
        opacity: root.haloVisible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
    }

    Rectangle {
        color: "transparent"
        z: -1
        anchors.horizontalCenter: parent.horizontalCenter
        y: islandRect.y - root.haloW * 0.65
        width: islandRect.width + root.haloW * 1.3
        height: islandRect.height + root.haloW * 1.3
        radius: islandRect.radius + root.haloW * 0.65
        border.width: root.haloBorderW
        border.color: Qt.rgba(1, 1, 1, root.haloPeakA * 0.55)
        opacity: root.haloVisible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
    }

    Rectangle {
        color: "transparent"
        z: -1
        anchors.horizontalCenter: parent.horizontalCenter
        y: islandRect.y - root.haloW
        width: islandRect.width + root.haloW * 2
        height: islandRect.height + root.haloW * 2
        radius: islandRect.radius + root.haloW
        border.width: root.haloBorderW
        border.color: Qt.rgba(1, 1, 1, root.haloPeakA * 0.3)
        opacity: root.haloVisible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
    }

    // Gesture layer sits BELOW the island content: bar clicks/hoovers reach
    // the indicators above, presses on gaps and outside the island land here.
    GestureZones {
        anchors.fill: parent
        active: true
        isMinimal: root.state.currentState === root.state.minimal && !root.temporaryRevealFromMinimal
        moduleOpen: root.moduleOpen
        islandX: root.islandX
        islandY: root.islandY
        islandWidth: root.islandWidth
        islandHeight: root.islandHeight
        cfg: root.gestureCfg
        onRequestPresentationMinimal: {
            root.state.setMinimal();
            minimalIdle.restart();
        }
        onRequestQuickSettings: root.openQuickSettings()
        onRequestNotificationCenter: root.openNotificationCenter()
        onRequestCloseModule: {
            if (root.moduleOpen)
                root.closeModule();
        }
        onMinimalHoldChanged: active => {
            root.temporaryRevealFromMinimal = active;
            if (active) {
                root.holdRevealing = true;
                root.state.setIsland();
            } else if (root.holdRevealing) {
                root.holdRevealing = false;
                root.state.setMinimal();
            }
            minimalIdle.restart();
        }
        onMinimalSwipeDown: {
            // Commit the reveal: stay in Island instead of dropping back.
            root.holdRevealing = false;
            root.temporaryRevealFromMinimal = false;
            root.state.setIsland();
            minimalIdle.restart();
        }
        onDashboardDragProgress: dy => {
            if (dy <= 0)
                return;
            root.dashboardDragging = true;
            if (!root.moduleOpen)
                root.openModule("dashboard", {});
            root.dashboardPreviewDy = dy;
        }
        onDashboardDragReleased: dy => {
            root.dashboardDragging = false;
            if (root.state.activeModule === "dashboard" && dy < root.gestureCfg.dashboardDragThreshold)
                root.closeModule();
        }
    }

    Rectangle {
        id: islandRect
        // Horizontally centered via anchor (NOT x:islandX + spring): at
        // startup islandWidth grows as indicators load and the layer width
        // settles, so an animated x would sweep left->center while y slides
        // top->position -- a diagonal flight from the top-left corner.
        // With anchor centering the width spring alone grows the island
        // symmetrically, and startup animates Y only (appearFromEdge).
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.islandY
        width: root.islandWidth
        height: root.islandHeight
        radius: root.islandRadius
        color: root.shouldDrawIslandShape
            ? Qt.rgba(root.theme.islandBg.r, root.theme.islandBg.g, root.theme.islandBg.b, root.config.effects.islandOpacity)
            : Qt.rgba(root.theme.minimalBg.r, root.theme.minimalBg.g, root.theme.minimalBg.b, root.theme.minimalOpacity)
        // DMS-style rim, only while compositor blur is on: a 1px border
        // over the island edge masks the zone where the hard compositor
        // blur mask diverges from the smooth painted corner (see blur block
        // above). With compositor blur off the rim just lightens the true
        // black edge, so it is dropped (width 0).
        border.width: root.config.effects.disableCompositorBlur ? 0 : root.theme.islandRimWidth
        border.color: root.theme.islandRim
        clip: true

        Behavior on width { Spring {} }
        Behavior on height { Spring {} }
        Behavior on radius { Spring {} }
        Behavior on y { Spring {} }

        ContentSwap {
            anchors.fill: parent
            showing: true
            swapKey: root.contentKey
            // Wash layer follows the island's (animated) corner radius.
            surfaceRadius: islandRect.radius
            blurEnabled: !root.config.effects.disableBlur
            blurInMs: root.timingCfg.blurInMs
            fadeInMs: root.timingCfg.fadeInMs
            blurOutMs: root.timingCfg.blurOutMs
            fadeOutMs: root.timingCfg.fadeOutMs
            stageDelayMs: root.timingCfg.blurFadeDelayMs

            // Bar content (indicators + clock). Fades out via its own
            // opacity when a module takes over (spec: blur->fade hide),
            // and stays hidden while the island is a bare Minimal strip.
            Item {
                anchors.fill: parent
                visible: opacity > 0.01
                opacity: root.showBarContent && root.shouldDrawIslandShape ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: root.timingCfg.fadeOutMs } }

                IndicatorLayout {
                    id: indicators
                    anchors.fill: parent
                    cfg: root.indicatorCfg
                    islandCfg: root.islandCfg
                    clock: root.clock
                    islandHeight: root.islandHeight
                    timingCfg: root.timingCfg
                    audio: root.audio
                    players: root.players
                    network: root.network
                    recorder: root.recorder
                    dictation: root.dictation
                    theme: root.theme
                    onRequestModule: (name, payload) => root.openModule(name, payload)
                }
            }

            ModuleHost {
                anchors.fill: parent
                visible: root.moduleOpen
                moduleName: root.state.activeModule
                payload: root.state.activePayload
                services: ({
                        audio: root.audio,
                        players: root.players,
                        network: root.network,
                        bluetooth: root.bluetooth,
                        brightness: root.brightness,
                        notifications: root.notifications,
                        recorder: root.recorder,
                        dictation: root.dictation,
                        systemUsage: root.systemUsage,
                        weather: root.weather,
                        clock: root.clock,
                        battery: root.battery,
                        compositor: root.compositor,
                        config: root.config,
                        theme: root.theme
                    })
                onCloseRequested: root.closeModule()
            }

            // Notification ticker in the Minimal-revealed bar: overlays the
            // bar content without replacing it (spec).
            Item {
                anchors.fill: parent
                visible: opacity > 0.01
                opacity: root.tickerVisible && !root.moduleOpen ? 1 : 0
                clip: true
                Behavior on opacity { NumberAnimation { duration: root.timingCfg.fadeInMs } }

                Text {
                    id: tickerLabel
                    y: (parent.height - height) / 2
                    x: tickerAnim.running ? width : indicators.edgePad
                    text: root.tickerText
                    color: root.theme.islandFg
                    font.pixelSize: root.theme.fontSizeBody
                }
                SequentialAnimation {
                    id: tickerAnim
                    running: root.tickerVisible
                    loops: Animation.Infinite
                    NumberAnimation {
                        target: tickerLabel
                        property: "x"
                        from: islandRect.width
                        to: -tickerLabel.width
                        duration: root.config.notifications.tickerDurationMs
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "island"
        function launcher(): void { root.openLauncher(); }
        function quicksettings(): void { root.openQuickSettings(); }
        function notifications(): void { root.openNotificationCenter(); }
        function capture(): void { root.openCapture(); }
        function dashboard(): void { root.openModule("dashboard", {}); }
        function player(): void { root.openModule("player", {}); }
        function lock(): void { root.openLock(); }
        function close(): void {
            if (root.moduleOpen)
                root.closeModule();
        }
        function minimal(): void { root.state.setMinimal(); }
        function island(): void { root.state.setIsland(); }
        function osd(title: string, icon: string, value: real): void { root.showOsd(title, icon, value); }

        // Key-driven OSD (bind in niri: qs -c pillShell ipc call island <fn>)
        function volumeUp(): void {
            root.audio.incrementVolume();
            root.showOsd("Volume", root.audio.muted ? "🔇" : "🔊", root.audio.volume);
        }
        function volumeDown(): void {
            root.audio.decrementVolume();
            root.showOsd("Volume", root.audio.muted ? "🔇" : "🔊", root.audio.volume);
        }
        function volumeMute(): void {
            root.audio.toggleMute();
            root.showOsd("Volume", root.audio.muted ? "🔇" : "🔊", root.audio.volume);
        }
        function micMute(): void {
            root.audio.toggleSourceMute();
            root.showOsd("Microphone", "🎙", root.audio.sourceMuted ? 0 : root.audio.sourceVolume);
        }
        function brightnessUp(): void {
            root.brightness.increase();
            root.showOsd("Brightness", "☀", root.brightness.brightness);
        }
        function brightnessDown(): void {
            root.brightness.decrease();
            root.showOsd("Brightness", "☀", root.brightness.brightness);
        }
        function playPause(): void { root.players.playPause(); }
        function nextTrack(): void { root.players.next(); }
        function prevTrack(): void { root.players.previous(); }

        // Runtime introspection (debugging the state machine headlessly).
        function debugState(): string {
            return JSON.stringify({
                    state: root.state.currentState,
                    previousState: root.state.previousState,
                    activeModule: root.state.activeModule,
                    openCount: root.state.openCount,
                    island: [root.islandX, root.islandY, root.islandWidth, root.islandHeight],
                    started: root.started,
                    fsActive: root.fsActive,
                    ticker: root.tickerVisible,
                    contentKey: root.contentKey,
                    locked: root.lock.locked,
                    queue: root.notificationQueue.size,
                    mic: {
                        active: root.audio.micActive,
                        app: root.audio.micAppName,
                        streams: root.audio.captureStreams.length
                    },
                    bar: {
                        fitted: root.barFittedWidth,
                        stable: indicators.stableRowWidth,
                        row: indicators.barRowWidth,
                        kept: indicators.keptCount,
                        clock: indicators.clockWidth,
                        edgeD: indicators.edgePadD,
                        loaders: indicators.loaderState
                    }
                });
        }
    }
}
