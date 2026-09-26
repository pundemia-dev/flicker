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
    // Keep the layer surface tight around the island so it does not block
    // clicks to windows below; mouse-grab during drags still tracks outside.
    // In the bar state the side arcs stick out past the island (concentric
    // with the end roundings), so the surface also covers their overhang.
    readonly property real arcsBottom: root.islandY + root.islandHeight / 2 + arcsShape.extent + 1
    implicitHeight: Math.max(root.islandY + root.islandHeight + 8,
        (root.shouldDrawIslandShape && !root.moduleOpen) ? root.arcsBottom : 0,
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
    // appearFromEdge primitive: the island slides in from the top edge at startup.
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

    // Bar width fits the content (spec: no fixed bar width): clock centered,
    // indicator sides mirrored, capped at islandCfg.maxWidth (eviction in
    // IndicatorLayout kicks in past the cap).
    readonly property real barFittedWidth: {
        const left = indicators.leftContentWidth;
        const right = indicators.rightContentWidth;
        const clock = clockPlate.implicitWidth;
        const side = Math.max(left, right);
        const gaps = (left > 0 || right > 0) ? indicators.spacing * 2 : 0;
        return indicators.edgePad * 2 + clock + side * 2 + gaps;
    }

    readonly property real islandWidth: root.moduleOpen
        ? root.moduleSize.width
        : (root.shouldDrawIslandShape ? Math.min(root.barFittedWidth, root.islandCfg.maxWidth) : root.islandCfg.minimalWidth)
    readonly property real islandHeight: root.moduleOpen
        ? (root.dashboardDragging ? Math.min(root.moduleSize.height, root.islandCfg.height + root.dashboardPreviewDy) : root.moduleSize.height)
        : (root.shouldDrawIslandShape ? root.islandCfg.height : root.islandCfg.minimalHeight)
    readonly property real islandRadius: shouldDrawIslandShape ? islandCfg.radius : islandCfg.minimalRadius
    readonly property real islandX: (width - islandWidth) / 2
    readonly property real islandY: started ? islandCfg.topMargin : -(islandCfg.height + islandCfg.topMargin)

    Component.onCompleted: startupTimer.start()

    // Real backdrop blur via niri's ext-background-effect-v1 (pShell pattern):
    // the island rect is published as the compositor blur region. Two region
    // objects alternate (ping-pong): re-assigning the SAME object is a no-op
    // for the compositor, so every kick must present a different object;
    // assigning null clears the effect. While the island morphs the region
    // is held at null (pShell: never blur the morphing shape) and re-applied
    // once the springs settle. Visible behind translucent island areas.
    //
    // Pixel-exactness note: quickshell bakes Region radius into wl_region
    // as an integer QRegion-ellipse staircase and niri blurs exactly that
    // shape (layer surface, no layer-rule -> xray path, clip None,
    // radius 0), so an exact-fit region fringes ~1px of blurred background
    // past the smooth painted corner. While the island is opaque that fringe
    // is hidden by insetting the region (blurInsetEff, animated); while
    // translucent the region stays exact-fit so no seam rings inside.
    property bool blurAlt: false
    property bool blurSettled: true
    property string blurGeo: ""
    readonly property int blurBaseX: Math.round(islandRect.x)
    readonly property int blurBaseY: Math.round(islandRect.y)
    readonly property int blurBaseW: Math.round(islandRect.width)
    readonly property int blurBaseH: Math.round(islandRect.height)
    readonly property int blurBaseR: Math.round(islandRect.radius)
    // Dynamic blur inset (px, animated with the island morphs, never sharp):
    // opaque island -> effects.blurInset (fringe hidden underneath, blur is
    // occluded anyway); translucent island / Minimal -> effects.blurInsetFaded
    // (default 0, exact-fit, so no unblurred seam rings inside the bar).
    // blurInsetAnim rides the same springs as the resize; the int region
    // steps along the way and each step re-kicks the blur live.
    readonly property int blurInsetCfg: Math.max(0, root.config.effects?.blurInset ?? 2)
    // Inset for the translucent island (opacity < 1, Minimal strip): an
    // inset would ring an unblurred seam inside the bar, so the default is
    // an exact-fit region; tune up if the corner fringe bothers more.
    readonly property int blurInsetFadedCfg: Math.max(0, root.config.effects?.blurInsetFaded ?? 0)
    readonly property bool blurIsOpaque: root.shouldDrawIslandShape && (root.config.effects?.islandOpacity ?? 1) >= 1.0
    readonly property int blurInsetTarget: root.blurIsOpaque ? root.blurInsetCfg : root.blurInsetFadedCfg
    property real blurInsetAnim: root.blurInsetTarget
    Behavior on blurInsetAnim { Spring {} }
    readonly property int blurInsetEff: Math.max(0, Math.min(Math.round(root.blurInsetAnim), Math.floor(root.blurBaseW / 2), Math.floor(root.blurBaseH / 2)))
    readonly property int blurRegX: root.blurBaseX + root.blurInsetEff
    readonly property int blurRegY: root.blurBaseY + root.blurInsetEff
    readonly property int blurRegW: Math.max(0, root.blurBaseW - 2 * root.blurInsetEff)
    readonly property int blurRegH: Math.max(0, root.blurBaseH - 2 * root.blurInsetEff)
    readonly property int blurRegR: Math.max(0, root.blurBaseR - root.blurInsetEff)
    onBlurInsetAnimChanged: root.updateIslandBlur()

    function updateIslandBlur(): void {
        if (root.config.effects.disableBlur) {
            root.BackgroundEffect.blurRegion = null;
            root.blurGeo = "";
            return;
        }
        if (!root.blurSettled) {
            root.BackgroundEffect.blurRegion = null;
            return;
        }
        const g = `${root.blurRegX},${root.blurRegY},${root.blurRegW},${root.blurRegH},${root.blurRegR}`;
        if (g === root.blurGeo)
            return;
        root.blurGeo = g;
        root.blurAlt = !root.blurAlt;
        root.BackgroundEffect.blurRegion = root.blurAlt ? islandBlurRegionA : islandBlurRegionB;
    }

    // Called on every island morph trigger: drop the blur now, re-apply it
    // once the springs settle (debounced).
    function morphBlurHold(): void {
        root.blurSettled = false;
        blurSettleTimer.restart();
        root.updateIslandBlur();
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
        }
    }

    // Blur-region refresh triggers: state transitions + every island morph
    // hold the blur at null; the settle timer re-applies it once springs
    // stop. The heartbeat is a safety net (e.g. for the disableBlur config
    // toggle, which has no change signal on the nested JsonAdapter object).
    Connections {
        target: root.state
        function onCurrentStateChanged(): void { root.morphBlurHold(); }
        function onActiveModuleChanged(): void { root.morphBlurHold(); }
    }

    Connections {
        target: islandRect
        function onXChanged(): void { root.morphBlurHold(); }
        function onYChanged(): void { root.morphBlurHold(); }
        function onWidthChanged(): void { root.morphBlurHold(); }
        function onHeightChanged(): void { root.morphBlurHold(); }
        function onRadiusChanged(): void { root.morphBlurHold(); }
    }

    Timer {
        id: blurSettleTimer
        interval: 450
        onTriggered: {
            root.blurSettled = true;
            root.updateIslandBlur();
        }
    }

    Timer {
        id: blurHeartbeat
        interval: 2000
        repeat: true
        running: true
        onTriggered: root.updateIslandBlur()
    }

    // Compositor blur regions (ping-pong pair): the island rounded rect in
    // surface-local int coords, inset while opaque (see above). Both track
    // the live geometry; kicks alternate.
    Region {
        id: islandBlurRegionA
        x: root.blurRegX
        y: root.blurRegY
        width: root.blurRegW
        height: root.blurRegH
        radius: root.blurRegR
    }
    Region {
        id: islandBlurRegionB
        x: root.blurRegX
        y: root.blurRegY
        width: root.blurRegW
        height: root.blurRegH
        radius: root.blurRegR
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
        x: root.islandX
        y: root.islandY
        width: root.islandWidth
        height: root.islandHeight
        radius: root.islandRadius
        color: root.shouldDrawIslandShape
            ? Qt.rgba(root.theme.islandBg.r, root.theme.islandBg.g, root.theme.islandBg.b, root.config.effects.islandOpacity)
            : Qt.rgba(root.theme.minimalBg.r, root.theme.minimalBg.g, root.theme.minimalBg.b, root.theme.minimalOpacity)
        clip: true

        Behavior on width { Spring {} }
        Behavior on height { Spring {} }
        Behavior on radius { Spring {} }
        Behavior on x { Spring {} }
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
                    clockWidth: clockPlate.implicitWidth
                    audio: root.audio
                    players: root.players
                    network: root.network
                    recorder: root.recorder
                    dictation: root.dictation
                    theme: root.theme
                    onRequestModule: (name, payload) => root.openModule(name, payload)
                }

                ClockPlate {
                    id: clockPlate
                    anchors.centerIn: parent
                    clock: root.clock
                    recorder: root.recorder
                    network: root.network
                    theme: root.theme
                    islandHeight: root.islandHeight
                    cfg: root.indicatorCfg
                    timingCfg: root.timingCfg
                    onRequestModule: name => root.openModule(name, {})
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
                    queue: root.notificationQueue.size
                });
        }
    }
}
