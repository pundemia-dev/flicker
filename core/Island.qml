import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import "../components"
import "../modules/dashboard/DashMetrics.js" as DashMetrics
import "../modules/stash/StashMetrics.js" as StashMetrics
import "../modules/quicksettings/QsMetrics.js" as QsMetrics
import "../modules/launcher/LauncherMetrics.js" as LauncherMetrics
import "../modules/session/SessionActions.js" as SessionActions
import "../components/Knockout.js" as Knockout

PanelWindow {
    id: root
    // NOT named `screen`: that would shadow WindowInterface.screen, so the
    // real window screen is never set and every island lands on one output.
    required property ShellScreen targetScreen
    required property var config
    required property var theme
    required property var compositor
    required property var clock
    required property var audio
    required property var privacy
    required property var events
    required property var caffeine
    required property var players
    required property var network
    required property var bluetooth
    required property var battery
    required property var brightness
    required property var notifications
    required property var recorder
    required property var dictation
    required property var systemUsage
    required property var sensors
    required property var weather
    required property var lock
    // Capture orchestrator (modules/capture/CaptureScope, shell-level).
    required property var capture
    // File tray + LocalSend (services/Stash, services/LocalSend).
    required property var stash
    required property var localSend
    // Quick Settings layout state (services/ControlCenter).
    required property var controlCenter
    required property var haptics
    // Polkit agent (services/Polkit); the prompt is the `polkit` module.
    required property var polkit
    // Teleprompter (services/Prompter); shown as the `prompter` module.
    required property var prompter
    required property var wallpaper
    // Countdown timer (services/Countdown); the `timer` module + bar ring.
    required property var countdown
    // Music recognition (services/Shazam): the QS `shazam` card.
    required property var shazam
    required property var session
    // Keyboard pill policy (services/KeyboardIndicator): layout / Caps Lock.
    required property var keyboard
    // Shared per-screen island registry (IPC routes to the focused output).
    required property var registry

    screen: root.targetScreen
    color: "transparent"
    visible: !root.lock.locked
    // Overlay (not Top): niri does not composite Top-layer surfaces above a
    // fullscreen window, but Overlay stays visible. The spec requires the
    // island (minimal strip, tickers, modules opened from minimal) to work
    // during fullscreen, so the island lives on Overlay.
    WlrLayershell.layer: WlrLayer.Overlay
    // Keyboard only while a module needs it. Launcher: Exclusive (pShell
    // NiriFocusGrab) — OnDemand only focuses on a click, so a hotkey from a
    // focused text field left the search pill deaf. Notification center
    // mini-games: OnDemand (focus on click, never steals from windows).
    // Polkit prompt: Exclusive too (pkexec from a focused terminal).
    // Timer: Exclusive while setting it up (ruler keys right away), on
    // demand once it runs (an open countdown must not hold the keyboard).
    // Notification reply field (flow card long press): Exclusive while it is open.
    // Session menu: Exclusive (arrows / Enter right away).
    // Exclusive keyboard: a shell text field has it (the keyboard pill's
    // caret then belongs to this surface, not to the focused app window).
    readonly property bool takesKeyboard: root.state.activeModule === "launcher" || root.state.activeModule === "polkit"
        || (root.state.activeModule === "timer" && !root.countdown.active)
        || root.state.activeModule === "session"
        || (root.state.activeModule === "notifications" && moduleHost.wantsKeyboard)
    WlrLayershell.keyboardFocus: root.takesKeyboard ? WlrKeyboardFocus.Exclusive
        : ((root.state.activeModule === "notifications" && (root.state.activePayload?.mode ?? "") === "center")
            || root.state.activeModule === "prompter" || root.state.activeModule === "timer")
        ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    // Own namespace so compositor rules can target the island (niri
    // `layer-rule { match namespace="^pillShell-island$" }` with
    // `background-effect { xray false }` blurs the windows under it).
    WlrLayershell.namespace: "pillShell-island"
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
        // Drop chooser opened from the Minimal zone: keep the band above the
        // island in the mask, or the drag leaves the surface there.
        Region {
            x: Math.round(root.islandX)
            y: 0
            width: root.stashDropOpen ? Math.round(root.islandWidth) : 0
            height: Math.round(root.islandY)
        }
        // Minimal active zone (spec): from the top screen edge down past the
        // strip, so presses above the strip land here instead of falling
        // through to the window below.
        Region {
            x: Math.round((root.width - root.gestureCfg.minimalActiveZoneWidth) / 2)
            y: 0
            width: root.minimalZoneActive ? Math.round(root.gestureCfg.minimalActiveZoneWidth) : 0
            height: Math.round(root.gestureCfg.minimalActiveZoneHeight)
        }
    }
    // The layer surface stays tight around the island (plus arcs overhang
    // and the minimal active zone) purely to keep the window small; input
    // is gated by the mask above, so surface size alone never blocks clicks.
    // In the bar state the side arcs stick out past the island (concentric
    // with the end roundings), so the surface also covers their overhang.
    readonly property real arcsBottom: root.islandY + root.islandHeight / 2 + arcsShape.extent + 1
    // Lowest painted edge: the TARGET island bottom (so the surface grows at
    // once when a module opens), the ANIMATED body (so it shrinks only as
    // the spring does — sizing from the target alone cut the collapsing
    // island and the shared element flying home off at the bottom), and an
    // element in flight in the TransitionLayer.
    readonly property real paintBottom: Math.max(root.islandY + root.islandHeight,
        islandRect.y + islandRect.height, transitionLayer.flightBottom, ringLayer.flightBottom, root.surfaceReserve)
    // The Notification Center resizes itself while open (group fan-out,
    // dismissals): reserve its cap height for the whole session so those
    // morphs never resize the layer surface mid-animation (a frame stall).
    // Same for the launcher: its list resizes the island on every keystroke.
    readonly property real surfaceReserve: !root.moduleOpen ? 0
        : root.moduleKey === "notifications:center"
        ? root.islandY + ((root.config.modules ?? {})["notifications:center"]?.height ?? 0)
        : root.moduleKey === "launcher" ? root.islandY + LauncherMetrics.maxHeight(root.config.launcher)
        // Flow card: its context panel (+ the rubber-band past it) is pulled
        // out by hand — no surface resizes under the finger.
        : root.moduleKey === "notifications:flow" ? root.islandY + ((root.config.modules ?? {})["notifications:flow"]?.height ?? 0)
            + 2 * (root.config.notifications.flowActionHeight + root.config.notifications.flowActionSpacing) : 0
    // The surface must NOT follow paintBottom per frame: every layer-shell
    // resize reallocates the buffer and round-trips the compositor, which
    // froze collapse transitions. Grow at once (ratchet up), hold the peak
    // while anything still moves, shrink ONCE when everything has settled:
    // at most two resizes per transition. The extra area is transparent and
    // outside the input mask.
    property real heldBottom: 0
    // Rounded up with headroom: spring overshoot (a few px) must not trigger
    // a resize per frame.
    function surfaceStep(v: real): real {
        return Math.ceil((v + 8) / 16) * 16;
    }
    onPaintBottomChanged: if (root.paintBottom > root.heldBottom) root.heldBottom = root.surfaceStep(root.paintBottom)
    readonly property bool geometrySettled: Math.abs(islandRect.height - root.islandHeight) < 0.5
        && Math.abs(islandRect.y - root.islandY) < 0.5 && transitionLayer.flightBottom === 0 && ringLayer.flightBottom === 0
    onGeometrySettledChanged: if (root.geometrySettled) surfaceShrink.restart()
    Timer {
        id: surfaceShrink
        interval: 60
        onTriggered: if (root.geometrySettled) root.heldBottom = root.surfaceStep(root.paintBottom)
    }
    implicitHeight: Math.max(root.heldBottom + 8,
        (root.shouldDrawIslandShape && !root.moduleOpen) ? root.arcsBottom : 0,
        root.haloVisible ? root.heldBottom + root.haloPad + 1 : 0,
        gestureCfg.minimalActiveZoneHeight + 8)

    // Capture: the island background has been handed to the capture square;
    // the island is invisible (not unmapped) until it replays appearFromEdge.
    property bool stolen: false
    // Island size when capture opened: the empty capture module keeps it, so
    // only the content blur->fades out before the hand-over.
    property var captureFrom: ({ width: 0, height: 0 })
    // This island handed its background to the capture session: it stays a
    // Minimal strip (no startup morph / idle lift into the bar) until the
    // session ends, then expands back into the bar.
    property bool captureMinimal: false
    Binding {
        target: root.contentItem
        property: "opacity"
        value: root.stolen ? 0 : 1
    }

    property IslandState state: IslandState {}
    property NotificationQueue notificationQueue: NotificationQueue {}
    // When the flow card currently on screen started showing (for the
    // 5s → 3s shortening once more notifications queue up behind it).
    property double flowShownAt: 0
    // Dequeued card waiting out the collapse-to-bar gap before showing.
    property var pendingFlow: null
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
    // Bare strip (no hold reveal / ticker): the minimal active zone is live.
    readonly property bool minimalZoneActive: minimal && !temporaryRevealFromMinimal && !tickerVisible
    readonly property bool moduleOpen: state.currentState === state.module
    // Per-screen compositor state (global value as fallback).
    readonly property var screenInfo: (compositor?.perScreen ?? {})[screen.name] ?? null
    readonly property bool fsActive: screenInfo ? (screenInfo.fullscreen ?? false) : (compositor?.fullscreen ?? false)
    // Identifies the current island content; changing it replays the
    // ContentSwap blur->fade transition (openCount makes re-opens of the
    // same module - e.g. queued notifications - replay the swap too).
    readonly property string contentKey: root.moduleOpen
        ? `module:${root.state.activeModule}:${root.state.openCount}`
        : (root.tickerVisible ? "ticker" : "bar")
    // Sequential bar -> Minimal (test): the island keeps the bar shape while
    // the arcs tuck under it, and collapses only once they report `tucked`
    // (arcsHoldTimeout is the safety net).
    property bool arcsHold: false
    readonly property bool shouldDrawIslandShape: !minimal || temporaryRevealFromMinimal || tickerVisible || arcsHold

    // Content actually rendered. Lags the state: ContentSwap commits it at
    // the swap midpoint (old content faded out), so the old module stays on
    // screen while it fades and the new one never pops in before its fade-in.
    // Payload goes live once the swap settles (in-place updates, e.g. OSD).
    property string shownModule: ""
    property var shownPayload: null
    property bool shownTicker: false
    readonly property var hostPayload: contentSwap.settled ? root.state.activePayload : root.shownPayload

    function commitShownContent(): void {
        // Payload before module: ModuleHost's Loader reads it on creation.
        root.shownPayload = root.moduleOpen ? root.state.activePayload : null;
        root.shownModule = root.moduleOpen ? root.state.activeModule : "";
        root.shownTicker = root.tickerVisible && !root.moduleOpen;
    }

    // Module size from config.modules (key "notifications:flow"/"notifications:center"
    // splits the notifications module by payload mode); island.moduleWidth/Height
    // is the fallback for unlisted names. Every module island is sized apart.
    readonly property string moduleKey: {
        if (root.state.activeModule === "stash")
            return `stash:${root.state.activePayload?.view ?? "tray"}`;
        if (root.state.activeModule === "stash-drop")
            return "stash:drop";
        if (root.state.activeModule === "notifications") {
            const mode = root.state.activePayload?.mode ?? "";
            if (mode !== "")
                return `notifications:${mode}`;
        }
        return root.state.activeModule;
    }
    readonly property var moduleSize: {
        if (root.moduleKey === "capture")
            return root.captureFrom;
        // Dashboard: derived from its grid metrics (unit, margins, spacing...),
        // incl. the concentric corner radius (card radius + margins).
        if (root.moduleKey === "dashboard")
            return DashMetrics.islandSize(root.config.dashboard);
        // Quick Settings: rows of the tallest (preview) page; edit mode adds
        // a drop row + the footer, several tabs add the rail.
        if (root.moduleKey === "quicksettings")
            return QsMetrics.islandSize(root.config.quicksettings, root.controlCenter.rows,
                root.controlCenter.editing, root.controlCenter.hiddenIds.length, root.controlCenter.railIcons);
        // Launcher fits its list (+ side panel); until it is rendered
        // (ContentSwap handover) assume a full list.
        if (root.moduleKey === "launcher") {
            const c = root.config.launcher;
            if (root.shownModule === "launcher" && moduleHost.preferredHeight > 0)
                return { width: moduleHost.preferredWidth, height: moduleHost.preferredHeight, radius: LauncherMetrics.radius(c) };
            return LauncherMetrics.estimate(c, root.state.activePayload?.plugin ?? "");
        }
        if (root.moduleKey === "prompter") {
            const c = root.config.prompter;
            return { width: c.width, height: c.height, radius: c.radius };
        }
        // Polkit prompt fits its content (message / command / status lines).
        if (root.moduleKey === "polkit") {
            const c = root.config.polkit;
            const h = root.shownModule === "polkit" && moduleHost.preferredHeight > 0
                ? moduleHost.preferredHeight : c.estimatedHeight;
            return { width: c.width, height: h, radius: c.padding + c.buttonHeight / 2 };
        }
        // Session menu: one row of round buttons (count from config).
        if (root.moduleKey === "session") {
            const c = root.config.session;
            return SessionActions.islandSize(c, SessionActions.known(c.actions).length);
        }
        // Stash views fit their content (file / device / incoming counts).
        if (root.moduleKey.startsWith("stash:"))
            return StashMetrics.islandSize(root.config.stash, root.moduleKey.slice(6), {
                files: root.stash.count,
                devices: root.localSend.devices.count,
                sending: root.localSend.phase === "sending",
                incomingText: root.localSend.request?.isText ?? false,
                incomingFiles: root.localSend.request?.files?.length ?? 1
            });
        const all = root.config.modules ?? {};
        const size = all[root.moduleKey] ?? all[root.state.activeModule]
            ?? ({ width: root.islandCfg.moduleWidth, height: root.islandCfg.moduleHeight });
        // Flow card: grows by its context panel / reply field (drag down,
        // long press) once it is the rendered module.
        if (root.moduleKey === "notifications:flow" && root.shownModule === "notifications"
            && (root.hostPayload?.mode ?? "") === "flow" && moduleHost.preferredHeight > 0)
            return { width: size.width, height: moduleHost.preferredHeight, radius: size.radius };
        return root.moduleKey === "notifications:center"
            ? ({ width: size.width, height: Math.min(size.height, root.centerFitHeight) })
            : size;
    }
    // Notification Center fits its content (config height = cap). Until the
    // module is rendered (ContentSwap handover) estimate it from the
    // history: empty = game deck height, else the cap.
    readonly property real centerFitHeight: {
        const rendered = root.shownModule === "notifications"
            && (root.hostPayload?.mode ?? "") === "center" ? moduleHost.preferredHeight : -1;
        if (rendered > 0)
            return rendered;
        return (root.notifications.history ?? []).length === 0
            ? root.config.notifications.gameHeight : Number.POSITIVE_INFINITY;
    }

    // Bar width fits the content (spec: no fixed bar width): a single Row
    // centered in the island (indicators + clock in spec order, nothing
    // pinned to the edges), so the clock shifts when an indicator grows
    // (e.g. the mic hover label). Follows the STABLE row target
    // (IndicatorLayout.stableRowWidth): the island spring then runs the same
    // curve as the indicator width springs — one synchronized motion, the
    // clock glides instead of teleporting. Capped at islandCfg.maxWidth
    // (eviction in IndicatorLayout kicks in past the cap).
    // + an event's wider half on BOTH sides (IndicatorLayout.eventSide):
    // the row stays centred while an event shows.
    readonly property real barFittedWidth: indicators.edgePadD * 2 + indicators.stableRowWidth + indicators.eventSide * 2

    readonly property real islandWidth: root.moduleOpen
        ? root.moduleSize.width
        : (root.shouldDrawIslandShape ? Math.min(root.barFittedWidth, root.islandCfg.maxWidth) : root.islandCfg.minimalWidth)
    readonly property real islandHeight: root.moduleOpen
        ? (root.dashboardDragging ? Math.min(root.moduleSize.height, root.islandCfg.height + root.dashboardPreviewDy) : root.moduleSize.height)
        : (root.shouldDrawIslandShape ? root.islandCfg.height : root.islandCfg.minimalHeight)
    readonly property real islandRadius: !shouldDrawIslandShape ? islandCfg.minimalRadius
        : (moduleOpen ? (moduleSize?.radius ?? islandCfg.radius) : islandCfg.radius)
    readonly property real islandX: (width - islandWidth) / 2
    readonly property real islandY: started ? islandCfg.topMargin : -(islandCfg.height + islandCfg.topMargin)

    // appearFromEdge (spec): the shell appears as the Minimal strip sliding
    // in from the top edge, then morphs into the bar on its spot. Starting
    // in Minimal (not Island) is what makes the first phase a thin strip.
    Component.onCompleted: {
        state.setMinimal();
        startupTimer.start();
        root.registry.register(root);
    }
    Component.onDestruction: root.registry.unregister(root)

    // Caffeine mode: an idle inhibitor on this surface (services/Caffeine).
    IdleInhibitor {
        window: root
        enabled: root.caffeine.active
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

    // Frost: per-module compositor blur (effects.frostModules, e.g. Quick
    // Settings + Notification Center). The region goes up at once while the
    // body is still opaque, then the body colour springs to Theme.frostBody
    // so the blur emerges smoothly; on the way back the region stays until
    // the body is opaque again. Independent of disableCompositorBlur (which
    // governs the always-on blur behind Minimal / islandOpacity < 1).
    // frostBody = iOS 18 Control Center backdrop, fitted from the user's
    // iPhone samples (black wall -> #262626, white -> #E9E3E3): a light grey
    // at ~0.235 alpha, it LIFTS black (no darkening scrim).
    readonly property bool frostTarget: !root.config.effects.disableBlur
        && (root.config.effects.frost ?? false) && root.moduleOpen
        && (root.config.effects.frostModules ?? []).includes(root.moduleKey)
    property real frostSpringP: frostTarget ? 1 : 0
    Behavior on frostSpringP {
        Spring {
            stiffness: root.config.effects.frostSpring ?? 3
            damp: root.config.effects.frostDamping ?? 0.5
            eps: 0.002
        }
    }
    // 0 = opaque rest, 1 = fully frosted (clamped: the spring overshoots).
    readonly property real frostProgress: Math.max(0, Math.min(1, root.frostSpringP))
    function mixColor(a: color, b: color, t: real): color {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t);
    }
    readonly property color restBodyColor: Qt.rgba(root.theme.islandBg.r, root.theme.islandBg.g, root.theme.islandBg.b, root.config.effects.islandOpacity ?? 1)
    // Frosted, the body itself goes fully clear: the backdrop tint is the
    // knockout shape below (painted only BETWEEN the module's buttons, which
    // sit straight on the blur — iOS 18 CC, fitted from the user's samples).
    readonly property color bodyColor: root.mixColor(root.restBodyColor, Qt.rgba(0, 0, 0, 0), root.frostProgress)
    // Edge fade / anything that should match the backdrop's look.
    readonly property color backdropColor: root.mixColor(root.restBodyColor, root.frostTint, root.frostProgress)
    // Frost tint per module: the prompter is dark glass (Theme.prompterBody)
    // instead of the light Control Center grey. Latched while frosted, so
    // the fade-out keeps the tint it faded in with.
    readonly property string frostWanted: root.frostTarget ? root.moduleKey : ""
    property string frostKey: ""
    onFrostWantedChanged: if (root.frostWanted !== "") root.frostKey = root.frostWanted
    readonly property color frostTint: root.frostKey === "prompter" ? root.theme.prompterBody : root.theme.frostBody

    // Knockouts of the SHOWN module (switch at the ContentSwap handover).
    // On the way out the last set is held, shifted with the top-centred
    // ghost, until the ghost has faded; a fill shape tints the holes while
    // the content is not (yet / any more) there, so holes never pop.
    readonly property string shownKey: root.shownModule === "notifications"
        ? `notifications:${root.hostPayload?.mode ?? ""}` : root.shownModule
    readonly property var liveKnockouts: (root.config.effects.frost ?? false)
        && (root.config.effects.frostModules ?? []).includes(root.shownKey) ? moduleHost.knockouts : []
    property var heldKnockouts: []
    property real heldWidth: 0
    onLiveKnockoutsChanged: {
        if (root.liveKnockouts.length > 0) {
            root.heldKnockouts = root.liveKnockouts;
            root.heldWidth = islandRect.width;
        }
    }
    readonly property real ghostOpacity: contentSwap.ghostOpacity
    onGhostOpacityChanged: {
        if (root.ghostOpacity < 0.001 && root.liveKnockouts.length === 0)
            root.heldKnockouts = [];
    }
    readonly property bool knockoutsLive: root.liveKnockouts.length > 0
    readonly property var knockoutHoles: {
        const w = islandRect.width, h = islandRect.height, R = islandRect.radius;
        const dx = root.knockoutsLive ? 0 : (w - root.heldWidth) / 2;
        const src = root.knockoutsLive ? root.liveKnockouts : root.heldKnockouts;
        const out = [];
        for (const k of src) {
            const c = Knockout.insideOutline(dx === 0 ? k : Knockout.hole(k.x + dx, k.y, k.w, k.h, k.r), w, h, R);
            if (c)
                out.push(c);
        }
        return out;
    }
    // Hole fill: content fading in after the handover / ghost fading out.
    readonly property real knockoutFill: root.knockoutsLive
        ? 1 - contentSwap.contentOpacity : 1 - root.ghostOpacity
    readonly property bool compositorBlurOn: !root.config.effects.disableBlur
        && (!root.config.effects.disableCompositorBlur || root.frostTarget
            || root.frostSpringP > 0.005)
    onCompositorBlurOnChanged: root.updateIslandBlur()
    // Handed to modules (stable object, so the services map never rebuilds):
    // backing layers (card surfaces, tracks, idle discs, tiles, pills) drop
    // to frostLayerOpacity together with the body; accent fills stay solid.
    QtObject {
        id: frostState
        readonly property real progress: root.frostProgress
        readonly property real layerAlpha: 1 - (1 - (root.config.effects.frostLayerOpacity ?? 0.5)) * root.frostProgress
        // Secondary layers (idle discs, pills, chips): alpha fade.
        function layerColor(c: color): color {
            return Qt.rgba(c.r, c.g, c.b, c.a * frostState.layerAlpha);
        }
        // Button surfaces (knocked out of the tint, on the bare blur):
        // morph to Theme.frostButton.
        function surface(c: color): color {
            return root.mixColor(c, root.theme.frostButton, root.frostProgress);
        }
    }

    function updateIslandBlur(): void {
        if (!root.compositorBlurOn) {
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
        fsRevealIdle.stop();
        if (root.moduleOpen)
            return;
        if (root.fsActive)
            root.state.setMinimal();
        else if (!root.tickerVisible && !root.temporaryRevealFromMinimal && !root.captureMinimal)
            root.state.setIsland();
    }

    // A pending polkit prompt owns the island: nothing replaces it (the
    // request would sit unanswered behind another module); its own
    // re-open (next request after a success) passes.
    readonly property bool polkitHolds: root.moduleOpen && root.state.activeModule === "polkit"
        && root.polkit.phase !== "idle"

    function openModule(name: string, payload: var): void {
        if (root.polkitHolds && name !== "polkit")
            return;
        if (name === "timer" && !payload?.timerRouted) {
            openTimer(payload?.ring ?? null);
            return;
        }
        // Shared element (spec): an indicator handing its element over
        // (payload.shared = contract holder) flies it into the module;
        // payload.sharedRing = a second one at the same time (timer ring).
        if (payload?.shared && transitionLayer.contractFor(payload.shared, name))
            transitionLayer.launch(payload.shared, name);
        if (payload?.sharedRing && ringLayer.contractFor(payload.sharedRing, name))
            ringLayer.launch(payload.sharedRing, name);
        state.openModule(name, payload);
        // Modules opened from Minimal return there after the idle timeout.
        if (state.currentState === state.module && state.previousState === state.minimal)
            moduleIdle.restart();
        else
            moduleIdle.stop();
        // Flow cards auto-close (5s alone, 3s with more queued); anything
        // else replaces the flow and takes over its timer.
        if (name === "notifications" && (payload?.mode ?? "") === "flow")
            armFlowTimer();
        else
            flowAutoClose.stop();
    }

    // (Re)arms the flow auto-close: 5s when nothing else waits, 3s when the
    // queue has more behind the current card.
    function armFlowTimer(): void {
        root.flowShownAt = Date.now();
        flowAutoClose.interval = root.notificationQueue.size > 0 ? root.config.notifications.flowShowQueuedMs : root.config.notifications.flowShowMs;
        flowAutoClose.restart();
    }

    // A new arrival queued behind the visible flow card shortens its total
    // time on screen to the queued budget (3s from when it appeared).
    function shortenFlow(): void {
        if (root.state.activeModule !== "notifications")
            return;
        if ((root.state.activePayload?.mode ?? "") !== "flow")
            return;
        // Being answered / its buttons open: the newcomer waits its turn.
        if (moduleHost.holdOpen)
            return;
        const target = root.config.notifications.flowShowQueuedMs;
        const elapsed = Date.now() - root.flowShownAt;
        if (elapsed >= target)
            root.closeModule();
        else {
            flowAutoClose.interval = target - elapsed;
            flowAutoClose.restart();
        }
    }

    // Flow card payload; the bar clock flies into the card's time slot
    // (shared element) unless the recording/hotspot plate has replaced it.
    function flowPayload(notif: var): var {
        return { notification: notif, mode: "flow", shared: indicators.clockOwner };
    }

    // Timer: from the visible bar the clock flies into the timer's time and
    // (while it runs) the ring unfolds into the perimeter; opened over
    // another module / from Minimal the module draws both itself. Again
    // while it is open (IPC toggle) = close.
    function openTimer(ring: var): void {
        if (root.moduleOpen && root.state.activeModule === "timer") {
            closeModule();
            return;
        }
        const fromBar = !root.moduleOpen && root.state.currentState === root.state.island && root.shownModule === "";
        openModule("timer", {
            timerRouted: true,
            shared: fromBar ? indicators.clockOwner : null,
            sharedRing: fromBar && root.countdown.active ? (ring ?? indicators.timerOwner) : null
        });
    }
    // The countdown rang: show it (done state: ringing bell, repeat / ✕).
    function showTimerDone(): void {
        if (root.lock.locked || root.stolen || root.capture.active || root.capture.grabbing)
            return;
        if (!(root.moduleOpen && root.state.activeModule === "timer"))
            openTimer(null);
    }
    // Closing the timer into the bar: the countdown flies into the clock and
    // the perimeter folds into the ring even when they did not fly in
    // (adopted from the module's slots first, then sent home).
    function sendTimerHome(): void {
        if (transitionLayer.phase === "" && indicators.clockOwner && transitionLayer.adopt(indicators.clockOwner, "timer"))
            transitionLayer.returnHome();
        if (ringLayer.phase === "" && root.countdown.active && indicators.timerOwner && ringLayer.adopt(indicators.timerOwner, "timer"))
            ringLayer.returnHome();
    }
    // Cancelled inside the module: the ring has no home any more (its
    // indicator collapses) — re-dock it there at once; the module's own
    // perimeter takes over and un-draws.
    Connections {
        target: root.countdown
        function onActiveChanged(): void {
            if (!root.countdown.active && ringLayer.module === "timer")
                Qt.callLater(ringLayer.abort);
        }
    }

    // Dashboard: the bar clock flies into the header's time (shared element).
    function openDashboard(): void {
        openModule("dashboard", { shared: indicators.clockOwner });
    }

    // Launcher, optionally straight into a plugin ("clipboard"). Toggles:
    // the same call while it is open closes it.
    function openLauncher(plugin: string): void {
        const p = plugin ?? "";
        if (root.state.activeModule === "launcher" && (root.state.activePayload?.plugin ?? "") === p) {
            closeModule();
            return;
        }
        openModule("launcher", { plugin: p });
    }

    function openQuickSettings(): void {
        openModule("quicksettings", {});
    }

    // Quick Settings actions that grab the screen (screenshot, code scan,
    // start recording): close first, act once the collapse has settled so the
    // frozen grab shows the clean bar, not the open grid.
    function runQuickAction(name: string): void {
        closeModule();
        quickActionTimer.action = name;
        quickActionTimer.restart();
    }
    Timer {
        id: quickActionTimer
        property string action: ""
        interval: root.config.quicksettings.actionDelayMs
        onTriggered: {
            if (action === "screenshot")
                root.openCapture("shot");
            else if (action === "scan")
                root.openCapture("scan");
            else if (action === "record" && !root.recorder.recording)
                root.openCapture("record");
        }
    }

    // Capture (spec): the screens are grabbed first (CaptureScope.begin),
    // then startCaptureSteal() blur->fades the content out at the current
    // size and hands the background over (stealForCapture). A second call
    // while capturing switches/cycles the capture mode.
    function openCapture(mode: string): void {
        if (root.lock.locked)
            return;
        root.capture.begin(root.screen, root.capture.active || root.capture.grabbing || root.stolen ? null : root, mode ?? "");
    }

    function startCaptureSteal(): void {
        root.captureFrom = { width: root.islandWidth, height: root.islandHeight };
        openModule("capture", {});
    }

    // Grab failed / cancelled before the hand-over.
    function abortCapture(): void {
        if (root.state.activeModule === "capture")
            root.closeModule();
    }

    // Global band the capture backdrop keeps LIVE (frozen elsewhere): the
    // island now and as the bar it re-appears as, up to the screen top.
    // Screen-local island rect for the lock screen: the password field
    // starts as a copy of the island right here and flies down (LockField).
    function lockRect(): var {
        return {
            x: islandRect.x,
            y: islandRect.y,
            width: islandRect.width,
            height: islandRect.height,
            radius: islandRect.radius,
            visible: root.visible && islandRect.width > 0,
            clock: root.lockClock()
        };
    }

    // The bar clock label (window coords = screen-local) when the bar shows
    // it: the lock clock starts on it and flies to its own spot (LockClock).
    function lockClock(): var {
        const home = indicators.clockOwner?.sharedHome;
        const label = indicators.clockOwner?.sharedElement;
        if (!home || !label || root.state.currentState !== root.state.island || root.contentKey !== "bar")
            return null;
        const p = home.mapToItem(null, 0, 0);
        return {
            x: p.x,
            y: p.y,
            width: home.width,
            height: home.height,
            pixelSize: label.font.pixelSize,
            weight: label.font.weight,
            family: label.font.family,
            color: String(label.color)
        };
    }

    function captureHole(): var {
        const pad = root.config.capture.holePad + root.haloPad;
        const w = Math.max(islandRect.width, Math.min(root.barFittedWidth, root.islandCfg.maxWidth)) + pad * 2;
        return {
            screen: root.screen?.name ?? "",
            x: (root.screen?.x ?? 0) + (root.width - w) / 2,
            y: root.screen?.y ?? 0,
            width: w,
            height: root.islandCfg.topMargin + Math.max(islandRect.height, root.islandCfg.height) + pad
        };
    }

    // The emptied island becomes the capture square: hand the global rect
    // over, vanish (springs off, so the reset below jumps), and replay
    // appearFromEdge as the "second instance" — strip slides in from the
    // top edge and morphs into the bar unless fullscreen.
    function stealForCapture(): void {
        if (root.state.activeModule !== "capture")
            return;
        const rect = {
            x: (root.screen?.x ?? 0) + islandRect.x,
            y: (root.screen?.y ?? 0) + islandRect.y,
            width: islandRect.width,
            height: islandRect.height,
            radius: islandRect.radius
        };
        if (!root.capture.steal(rect)) {
            root.closeModule();
            return;
        }
        root.stolen = true;
        root.captureMinimal = true;
        root.closeModule();
        root.state.setMinimal();
        root.started = false;
        captureReappear.restart();
    }

    // Steal once the old content has faded (handover + ghost fade-out).
    Timer {
        id: captureSteal
        interval: root.timingCfg.fadeOutMs
        onTriggered: root.stealForCapture()
    }
    onShownModuleChanged: if (root.shownModule === "capture") captureSteal.restart()

    Connections {
        target: root.capture
        function onActiveChanged(): void {
            root.releaseCaptureMinimal();
        }
        // Expand while the overlay fades out (its hole fill fades over it).
        function onClosingChanged(): void {
            root.releaseCaptureMinimal();
        }
    }
    function releaseCaptureMinimal(): void {
        if ((root.capture.active && !root.capture.closing) || !root.captureMinimal)
            return;
        root.captureMinimal = false;
        if (root.state.currentState === root.state.minimal && !root.fsActive)
            root.state.setIsland();
    }

    Timer {
        id: captureReappear
        interval: root.config.capture.secondIslandDelayMs
        onTriggered: {
            root.stolen = false;
            startupTimer.restart();
        }
    }

    function openPolkit(): void {
        polkitClose.stop();
        openModule("polkit", {});
    }

    // The flow ended: success holds the tick for successHoldMs first.
    Connections {
        target: root.polkit
        function onFinished(success: bool): void {
            if (!root.moduleOpen || root.state.activeModule !== "polkit")
                return;
            polkitClose.interval = success ? root.config.polkit.successHoldMs : 0;
            polkitClose.restart();
        }
    }
    Timer {
        id: polkitClose
        onTriggered: {
            root.polkit.settle();
            if (root.moduleOpen && root.state.activeModule === "polkit" && !root.polkit.active)
                root.closeModule();
        }
    }

    function openLock(): void {
        root.lock.activate();
    }

    function openNotificationCenter(): void {
        openModule("notifications", { mode: "center" });
    }

    // Stash tray (IPC + the QS LocalSend card). Lands on whatever flow is live: a pending
    // incoming LocalSend card, a running pick/upload, else the tray.
    function openStash(view: string): void {
        // Never over a capture session (the island is stolen / overlays own
        // the screen); a pending incoming card stays reachable via IPC.
        if (root.lock.locked || root.stolen || root.capture.active || root.capture.grabbing)
            return;
        const v = view !== "" ? view
            : root.localSend.hasIncoming ? "incoming"
            : root.localSend.busy ? "send" : "tray";
        openModule("stash", { view: v, returnView: v === "tray" ? "" : "tray" });
    }

    // Session menu (lock / log out / sleep / restart / shut down): toggle.
    function toggleSession(): void {
        if (root.moduleOpen && root.state.activeModule === "session")
            root.closeModule();
        else
            root.openModule("session", {});
    }

    function toggleStash(): void {
        if (root.moduleOpen && root.state.activeModule === "stash")
            root.closeModule();
        else
            root.openStash("");
    }

    // ── Stash drop chooser ──
    // A file drag over the island (or the Minimal zone) opens the chooser;
    // leaving it for dropLeaveMs closes it again (back to the tray when it
    // replaced the tray). Own tile drags (Stash.outgoingDrag) never count.
    readonly property bool stashDropOpen: root.moduleOpen && root.state.activeModule === "stash-drop"
    readonly property bool stashDragOver: islandDrop.containsDrag || moduleHost.dragActive

    function openStashDrop(): void {
        stashDropLeave.stop();
        if (root.stashDropOpen || root.lock.locked || root.stolen || root.stash.outgoingDrag
            || root.capture.active || root.capture.grabbing)
            return;
        const fromTray = root.moduleOpen && root.state.activeModule === "stash"
            && (root.state.activePayload?.view ?? "") === "tray";
        openModule("stash-drop", { returnView: fromTray ? "tray" : "" });
    }

    function leaveStashDrop(): void {
        if (!root.stashDropOpen)
            return;
        if ((root.state.activePayload?.returnView ?? "") === "tray")
            openModule("stash", { view: "tray" });
        else
            root.closeModule();
    }

    onStashDragOverChanged: {
        if (root.stashDragOver)
            stashDropLeave.stop();
        else if (root.stashDropOpen)
            stashDropLeave.restart();
    }

    Timer {
        id: stashDropLeave
        interval: root.config.stash.dropLeaveMs
        onTriggered: if (!root.stashDragOver) root.leaveStashDrop()
    }

    // payload: { kind: volume|mic|brightness|custom, value, muted, icon }
    // (see modules/osd/OsdModule.qml). A fresh object per key press — the
    // module rubber-bands on presses that hit an end.
    function showOsd(osd: var): void {
        // Never over the teleprompter (the text would blink away mid-read).
        if (root.moduleOpen && root.state.activeModule === "prompter")
            return;
        const payload = Object.assign({}, osd ?? {});
        // Already up: update in place. Re-opening bumps openCount and replays
        // the whole swap on every key repeat (the OSD flickers).
        if (root.moduleOpen && root.state.activeModule === "osd") {
            root.state.activePayload = payload;
            root.noteModuleInteraction();
        } else {
            openModule("osd", payload);
        }
        osdAutoClose.restart();
    }

    // Any interaction with a module opened from Minimal restarts its idle
    // timeout (spec: return after the LAST interaction).
    function noteModuleInteraction(): void {
        if (moduleIdle.running)
            moduleIdle.restart();
    }

    // ── Teleprompter ──
    // The prompter is a session: another module opened over it (launcher,
    // QS) hands the island back to it on close; only closing the prompter
    // itself (swipe up, Esc, IPC) ends it. `prompterHere` = this output owns
    // the session (services/Prompter is shared by all islands).
    property bool prompterHere: false

    function openPrompter(): void {
        if (root.lock.locked || root.stolen || root.capture.active || root.capture.grabbing)
            return;
        root.prompterHere = true;
        if (!(root.moduleOpen && root.state.activeModule === "prompter"))
            openModule("prompter", {});
    }

    Connections {
        target: root.prompter
        // Shown on another output now: hand the session over quietly.
        function onShowRequested() {
            if (!root.prompterHere || root.registry.forOutput(root.compositor?.focusedOutput ?? "") === root)
                return;
            root.prompterHere = false;
            if (root.moduleOpen && root.state.activeModule === "prompter")
                root.closeModule();
        }
        function onHideRequested() {
            root.prompterHere = false;
            if (root.moduleOpen && root.state.activeModule === "prompter")
                root.closeModule();
        }
    }

    function closeModule(): void {
        const closing = root.state.activeModule;
        // A rung timer is dismissed by closing it (alarm off).
        if (closing === "timer" && root.countdown.phase === "done")
            root.countdown.cancel();
        if (closing !== "prompter" && root.prompterHere && root.prompter.open) {
            moduleIdle.stop();
            flowAutoClose.stop();
            openModule("prompter", {});
            return;
        }
        // Closing the prompt (swipe up, Esc) = cancel the request.
        if (root.state.activeModule === "polkit" && root.polkit.active)
            root.polkit.cancel();
        polkitClose.stop();
        moduleIdle.stop();
        flowAutoClose.stop();
        state.closeModule();
        if (closing === "timer" && root.state.currentState === root.state.island)
            sendTimerHome();
        if (closing === "prompter" && root.prompterHere)
            root.prompter.close();
        // previousState may be stale: fullscreen changes are ignored while a
        // module is open (onFsActiveChanged), so reconcile here. Back in
        // Minimal without fullscreen, the idle timer must run or the strip
        // never returns to the bar.
        // Back in the bar under fullscreen (stale previousState, or a module
        // opened from the swiped-down bar): it hides like a revealed bar.
        if (root.state.currentState === root.state.island && root.fsActive && !root.temporaryRevealFromMinimal)
            root.armFsReveal();
        else if (root.state.currentState === root.state.minimal && !root.fsActive)
            minimalIdle.restart();
        // Queue advance goes through a visible collapse to the bar first:
        // hold the next card for the gap, then expand back with it.
        if (root.pendingFlow == null && notificationQueue.size > 0) {
            root.pendingFlow = notificationQueue.dequeue();
            flowSwapGap.restart();
        }
    }

    function showTicker(notif: var): void {
        tickerText = `${notif.appName}: ${notif.summary}`;
        tickerVisible = true;
        tickerTimer.restart();
    }

    Connections {
        target: root.notifications
        // Sender closed / expired / trimmed: never show it later, and take
        // the card down if it is the one on screen right now.
        function onNotificationClosed(notif) {
            root.notificationQueue.remove(notif);
            if (root.pendingFlow === notif)
                root.pendingFlow = null;
            if (root.moduleOpen && root.state.activeModule === "notifications"
                && root.state.activePayload?.notification === notif)
                root.closeModule();
        }
        function onNotificationReceived(notif) {
            const urgency = notif?.urgency ?? 1;
            if (root.config.notifications.onlyUrgentToast && urgency < 1)
                return;
            if (root.moduleOpen) {
                root.notificationQueue.enqueue(notif);
                root.shortenFlow();
                return;
            }
            if (root.state.currentState === root.state.minimal || root.fsActive) {
                root.showTicker(notif);
            } else {
                root.openModule("notifications", root.flowPayload(notif));
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

    // Fullscreen keeps the island Minimal. A swiped-down (revealed) bar
    // stays while the cursor is over it and hides back to Minimal
    // minimalIdleMs after the cursor leaves, if still fullscreen.
    // Always (re)arms under fullscreen: the trigger re-checks hover, since
    // hover state can be stale right after a drag grab is released.
    function armFsReveal(): void {
        if (root.fsActive)
            fsRevealIdle.restart();
        else
            fsRevealIdle.stop();
    }

    Timer {
        id: fsRevealIdle
        interval: root.timingCfg.minimalIdleMs
        onTriggered: {
            if (root.state.currentState !== root.state.island || !root.fsActive || root.temporaryRevealFromMinimal)
                return;
            if (islandHover.hovered)
                return; // leaving re-arms it (islandHover)
            root.state.setMinimal();
        }
    }

    Timer {
        id: arcsHoldTimeout
        interval: 1000
        onTriggered: root.arcsHold = false
    }

    Timer {
        id: minimalIdle
        interval: root.timingCfg.minimalIdleMs
        onTriggered: {
            if (root.state.currentState === root.state.minimal && !root.fsActive && !root.captureMinimal)
                root.state.setIsland();
        }
    }

    Timer {
        id: moduleIdle
        interval: root.timingCfg.moduleIdleFromMinimalMs
        onTriggered: {
            if (root.state.currentState !== root.state.module || root.state.previousState !== root.state.minimal)
                return;
            // Still in use: the cursor is over the island, or the launcher
            // owns the keyboard (it closes itself on Esc/launch).
            // HoverHandler does not see drags: a file held over the chooser
            // and a running device scan / upload count as use too.
            if (islandHover.hovered || root.state.activeModule === "launcher" || root.state.activeModule === "prompter" || root.polkitHolds || root.stash.outgoingDrag
                || root.stashDragOver || (root.state.activeModule === "stash" && root.localSend.busy)) {
                moduleIdle.restart();
                return;
            }
            root.closeModule();
        }
    }

    Timer {
        id: osdAutoClose
        interval: root.timingCfg.osdAutoCloseMs
        onTriggered: if (root.state.activeModule === "osd")
            root.closeModule()
    }

    // Flow toast lifetime (closeModule dequeues the next queued card, if any).
    Timer {
        id: flowAutoClose
        onTriggered: {
            if (root.state.activeModule !== "notifications" || (root.state.activePayload?.mode ?? "") !== "flow")
                return;
            // In use (pressed, buttons open, replying): check again later.
            if (moduleHost.holdOpen) {
                flowAutoClose.interval = root.config.notifications.flowShowQueuedMs;
                flowAutoClose.restart();
                return;
            }
            root.closeModule();
        }
    }

    // Collapse-to-bar gap between queued flow cards: the island visibly
    // shrinks to the bar, then expands back with the next card.
    Timer {
        id: flowSwapGap
        interval: root.config.notifications.flowSwapGapMs
        onTriggered: {
            const next = root.pendingFlow;
            root.pendingFlow = null;
            if (next == null)
                return;
            if (root.moduleOpen)
                // User opened something during the gap: put the card back
                // to the front of the queue, it shows after that closes.
                root.notificationQueue.requeue(next);
            else
                root.openModule("notifications", root.flowPayload(next));
        }
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
            if (!root.fsActive && !root.captureMinimal && root.state.currentState === root.state.minimal)
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
        function onCurrentStateChanged(): void {
            // Entering Minimal with the arcs on screen: hold the bar until
            // they tuck. The arcs' hide spring has not moved yet here, so
            // their opacity still tells whether they were visible.
            if (root.started && root.state.currentState === root.state.minimal
                && !root.temporaryRevealFromMinimal && arcsShape.opacity > 0.5) {
                root.arcsHold = true;
                arcsHoldTimeout.restart();
            } else if (root.state.currentState !== root.state.minimal) {
                root.arcsHold = false;
                arcsHoldTimeout.stop();
            }
            root.updateIslandBlur();
        }
        function onActiveModuleChanged(): void {
            // The shared element's module closed or was replaced: fly home.
            if (transitionLayer.module !== "" && root.state.activeModule !== transitionLayer.module)
                transitionLayer.returnHome();
            if (ringLayer.module !== "" && root.state.activeModule !== ringLayer.module)
                ringLayer.returnHome();
            root.updateIslandBlur();
        }
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
        onTucked: {
            root.arcsHold = false;
            arcsHoldTimeout.stop();
        }
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
        clockCenterX: islandRect.x + indicators.clockCenterX
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
            root.armFsReveal();
        }
        onDashboardDragProgress: dy => {
            if (dy <= 0)
                return;
            root.dashboardDragging = true;
            if (!root.moduleOpen)
                root.openDashboard();
            root.dashboardPreviewDy = dy;
        }
        onDashboardDragReleased: dy => {
            root.dashboardDragging = false;
            if (root.state.activeModule === "dashboard" && dy < root.gestureCfg.dashboardDragThreshold)
                root.closeModule();
        }
    }

    // Stash drop target: the island plus the band above it (and the whole
    // Minimal active zone while that is live). BELOW the island content, so
    // the chooser's own tiles get the drag first (ModuleHost.dragActive).
    DropArea {
        id: islandDrop
        readonly property real zoneW: root.minimalZoneActive ? root.gestureCfg.minimalActiveZoneWidth : 0
        width: Math.max(islandRect.width, islandDrop.zoneW)
        x: (root.width - islandDrop.width) / 2
        y: 0
        height: Math.max(islandRect.y + islandRect.height, root.minimalZoneActive ? root.gestureCfg.minimalActiveZoneHeight : 0)
        keys: ["text/uri-list"]
        onEntered: root.openStashDrop()
        onDropped: drop => {
            // Refused drag (locked / capture / own tile dragged back): leave
            // the drop alone instead of silently copying into the tray.
            if (!root.stashDropOpen)
                return;
            const paths = root.stash.pathsFromUrls(drop.urls);
            drop.accept();
            // Dropped before the chooser rendered (quick drop on the bar):
            // the tray is the default. On the chooser's gaps: cancel.
            if (root.shownModule !== "stash-drop" && paths.length > 0) {
                root.stash.drop(paths);
                root.leaveStashDrop();
            } else {
                root.leaveStashDrop();
            }
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
            ? root.bodyColor
            : Qt.rgba(root.theme.minimalBg.r, root.theme.minimalBg.g, root.theme.minimalBg.b, root.theme.minimalOpacity)
        // DMS-style rim, only while compositor blur is on: a 1px border
        // over the island edge masks the zone where the hard compositor
        // blur mask diverges from the smooth painted corner (see blur block
        // above). With compositor blur off the rim just lightens the true
        // black edge, so it is dropped (width 0).
        // Frost-only blur fades the rim in with the frost.
        border.width: root.compositorBlurOn ? root.theme.islandRimWidth : 0
        border.color: root.config.effects.disableCompositorBlur
            ? Qt.rgba(root.theme.islandRim.r, root.theme.islandRim.g, root.theme.islandRim.b, root.theme.islandRim.a * root.frostProgress)
            : root.theme.islandRim
        clip: true

        Behavior on width { enabled: !root.stolen; Spring {} }
        Behavior on height { enabled: !root.stolen; Spring {} }
        Behavior on radius { enabled: !root.stolen; Spring {} }
        Behavior on y { enabled: !root.stolen; Spring {} }

        // Passive hover tracker: keeps a module opened from Minimal alive
        // while the cursor is over it; leaving restarts the idle timeout.
        HoverHandler {
            id: islandHover
            onHoveredChanged: {
                root.noteModuleInteraction();
                if (root.state.currentState === root.state.island)
                    root.armFsReveal();
            }
        }

        // Frost backdrop tint with the module's buttons knocked out (even-odd:
        // outline + holes), and the hole fill used across content swaps.
        // Opacity only, never `visible`: a CurveRenderer Shape toggled via
        // visible never repaints again (AGENTS gotcha).
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            opacity: root.frostProgress
            ShapePath {
                fillColor: root.frostTint
                strokeWidth: -1
                fillRule: ShapePath.OddEvenFill
                PathSvg {
                    path: root.frostProgress > 0.001
                        ? Knockout.rectPath(Knockout.hole(0, 0, islandRect.width, islandRect.height, islandRect.radius))
                            + " " + Knockout.holesPath(root.knockoutHoles)
                        : ""
                }
            }
        }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            opacity: root.frostProgress * Math.max(0, Math.min(1, root.knockoutFill))
            ShapePath {
                fillColor: root.frostTint
                strokeWidth: -1
                PathSvg {
                    path: root.frostProgress > 0.001 && root.knockoutFill > 0.001
                        ? Knockout.holesPath(root.knockoutHoles) : ""
                }
            }
        }

        ContentSwap {
            id: contentSwap
            anchors.fill: parent
            onCommitted: root.commitShownContent()
            showing: true
            swapKey: root.contentKey
            // Wash layer follows the island's (animated) corner radius.
            surfaceRadius: islandRect.radius
            blurEnabled: !root.config.effects.disableBlur
            blurMax: root.config.effects.contentBlurMax ?? 32
            edgeFade: root.config.effects.contentEdgeFade ?? 24
            // Edge fade matches the (possibly frosted) body, else it paints
            // opaque bands over the translucent island.
            fadeColor: root.backdropColor
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
                opacity: root.shownModule === "" && root.shouldDrawIslandShape ? 1 : 0
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
                    privacy: root.privacy
                    events: root.events
                    players: root.players
                    network: root.network
                    recorder: root.recorder
                    dictation: root.dictation
                    theme: root.theme
                    countdown: root.countdown
                    onRequestModule: (name, payload) => root.openModule(name, payload)
                }
            }

            ModuleHost {
                id: moduleHost
                anchors.fill: parent
                visible: root.shownModule !== ""
                moduleName: root.shownModule
                payload: root.hostPayload
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
                        sensors: root.sensors,
                        weather: root.weather,
                        clock: root.clock,
                        battery: root.battery,
                        compositor: root.compositor,
                        config: root.config,
                        theme: root.theme,
                        frost: frostState,
                        stash: root.stash,
                        localSend: root.localSend,
                        controlCenter: root.controlCenter,
                        haptics: root.haptics,
                        polkit: root.polkit,
                        prompter: root.prompter,
                        countdown: root.countdown,
                        shazam: root.shazam,
                        session: root.session,
                        quickAction: root.runQuickAction,
                        openStash: root.openStash,
                        wallpaper: root.wallpaper,
                        // Launcher plugins: output + bar centre (normalized,
                        // y from the top) — the wallpaper "island" effect
                        // grows from there.
                        launcherHost: ({
                                haptics: root.haptics,
                                wallpaper: root.wallpaper,
                                prompter: root.prompter,
                                screen: root.targetScreen?.name ?? "",
                                originX: 0.5,
                                originY: (root.islandCfg.topMargin + root.islandCfg.height / 2) / Math.max(1, root.targetScreen?.height ?? 1)
                            })
                    })
                // Only the module still on screen as the active one: a flow
                // card tapped open is closed by its sender at the same time
                // (onNotificationClosed) — a second close poisoned the state.
                onCloseRequested: {
                    if (root.moduleOpen && root.state.activeModule === root.shownModule)
                        root.closeModule();
                }
                // Only the module that is still the active one may switch
                // (a fading-out module must not reopen anything).
                onOpenRequested: (name, payload) => {
                    if (root.moduleOpen && root.state.activeModule === root.shownModule)
                        root.openModule(name, payload);
                }
            }

            // Notification ticker in the Minimal-revealed bar: overlays the
            // bar content without replacing it (spec).
            Item {
                anchors.fill: parent
                visible: opacity > 0.01
                opacity: root.shownTicker && root.tickerVisible ? 1 : 0
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

    // Shared element transitions: above all island content (spec).
    TransitionLayer {
        id: transitionLayer
        slotResolver: (name, key) => moduleHost.sharedSlot(name, key)
    }
    // Second simultaneous flight (payload.sharedRing): the timer ring
    // unfolds into the perimeter while the clock flies into the time.
    TransitionLayer {
        id: ringLayer
        slotResolver: (name, key) => moduleHost.sharedSlot(name, key)
    }

    // IPC lives in IslandIpc (one handler routed to the focused output's
    // island); this is the introspection it exposes as debugState.
    function debugState(): string {
        return JSON.stringify({
                screen: root.screen?.name ?? "",
                state: root.state.currentState,
                shownModule: root.shownModule,
                previousState: root.state.previousState,
                activeModule: root.state.activeModule,
                openCount: root.state.openCount,
                island: [root.islandX, root.islandY, root.islandWidth, root.islandHeight],
                started: root.started,
                fsActive: root.fsActive,
                ticker: root.tickerVisible,
                contentKey: root.contentKey,
                locked: root.lock.locked,
                stolen: root.stolen,
                stash: {
                    files: root.stash.count,
                    dir: root.stash.stashDir,
                    dragOver: root.stashDragOver,
                    outgoing: root.stash.outgoingDrag,
                    send: root.localSend.phase,
                    devices: root.localSend.devices.count,
                    receiving: root.localSend.receiving,
                    incoming: root.localSend.hasIncoming
                },
                capture: root.capture.debugInfo(),
                prompter: JSON.parse(root.prompter.status()),
                queue: root.notificationQueue.size,
                notifCount: (root.notifications.history ?? []).length,
                notifs: (root.notifications.history ?? []).slice(0, 5).map(n => ({
                        app: n?.appName ?? "",
                        icon: n?.appIcon ?? "",
                        image: (n?.image ?? "").length > 0,
                        summary: n?.summary ?? ""
                    })),
                mic: {
                    active: root.audio.micActive,
                    app: root.audio.micAppName,
                    streams: root.audio.captureStreams.length
                },
                privacy: {
                    kind: root.privacy.kind,
                    app: root.privacy.appName,
                    screens: root.privacy.screenNodes.map(n => n.name),
                    cameras: root.privacy.cameraNodes.map(n => n.name),
                    cameraProcs: root.privacy.cameraProcs
                },
                caffeine: root.caffeine.active,
                keyboard: {
                    what: root.keyboard.what,
                    label: root.keyboard.label,
                    caps: root.keyboard.caps,
                    led: root.keyboard.ledPath,
                    pointer: root.keyboard.pointer,
                    probing: root.keyboard.probing,
                    caretActive: root.keyboard.caret.active,
                    caretRect: root.keyboard.caret.rect,
                    caretAnchor: root.keyboard.caret.anchor,
                    caretUnavailable: root.keyboard.caret.unavailable,
                    caretOffsets: root.keyboard.caret.calibration.offsets,
                    caretTries: root.keyboard.caret.calibration.tries
                },
                timer: {
                    phase: root.countdown.phase,
                    left: root.countdown.remainingText,
                    setup: root.countdown.setupMinutes,
                    clockFlight: transitionLayer.phase,
                    ringFlight: ringLayer.phase
                },
                events: {
                    current: root.events.current?.key ?? null,
                    queued: root.events.queue.map(e => e.key ?? "")
                },
                dictation: {
                    active: root.dictation.active,
                    phase: root.dictation.phase,
                    live: root.dictation.liveText,
                    typed: root.dictation.typedText,
                    last: root.dictation.lastTranscript,
                    error: root.dictation.lastError
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
