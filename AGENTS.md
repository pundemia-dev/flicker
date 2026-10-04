# AGENTS.md

## What this repo is

pillShell — a Wayland desktop shell on Quickshell (pure QML, no C++/build step): a single
"Dynamic Island" per monitor instead of a bar. The authoritative spec (Russian) is
`pillShell.md` — read the relevant section before implementing any feature/gesture/animation.
Reference implementation: `~/.config/quickshell/pShell` (also see its `CLAUDE.md` and
`docs/development/`). Per spec: check how pShell does something before writing an equivalent.

Not a git repo. No tests, no linter, no formatter.

## Run / verify

- Entry file MUST be `shell.qml` (Quickshell 0.3.1 loads `shell.qml`, ignores `main.qml`).
  Current content: `import "core"` + `Shell {}`.
- Smoke test: `timeout 8 quickshell -p $PWD 2>&1 | head -40` (needs a Wayland session; niri here).
- Runtime logs: stderr and `/run/user/1000/quickshell/by-id/<id>/log.qslog`.
- The user's live shell is pShell (separate `qs` process). Running pillShell in parallel is
  safe; these warnings are EXPECTED and harmless: "Could not register notification server at
  org.freedesktop.Notifications", portal "Connection already associated with an application ID".
- NEVER leave a background pillShell running: the user tests their own instance
  (`qs -c pillShell`) — two same-config instances overlap on screen (looks like
  mismatched radii!) and IPC routing between them is ambiguous. Before starting
  one, check BOTH forms: `pgrep -af "quickshell|qs -c"`. Kill yours immediately
  after (`kill <PID>`, literal PID — `pkill -f`/subshell kills are blocked).
- Visual check: `grim /tmp/shot.png`, crop top-center. NOTE: grim takes ~1.9s to
  capture, which exceeds the OSD auto-close (1.3s) — temporarily raise
  `timings.osdAutoCloseMs` in config.json when screenshotting short-lived states.
- IPC: `quickshell -p $PWD ipc call <target> <fn>` (with the user's instance running,
  address yours via `quickshell ipc --id <by-id dir> call ...`). `island` is ONE handler
  (`core/IslandIpc.qml`) routed via `core/IslandRegistry.qml` to the island on
  `compositor.focusedOutput` — never put an IpcHandler in per-screen Island. Targets: `island` (launcher, quicksettings,
  notifications, capture, dashboard, player, lock, close, minimal, island, osd, debugState,
  volumeUp/Down/Mute, micMute, brightnessUp/Down, playPause, nextTrack, prevTrack),
  `lock` (activate/isLocked — deliberately NO unlock/toggle over IPC; unlocking needs PAM),
  `dictation` (start/stop/toggle/cancel/status).

## Architecture wiring (non-obvious)

- `core/Shell.qml` owns single service instances and injects them into each per-screen
  `core/Island.qml` (a PanelWindow) as `required property var`. Adding a service means wiring
  Shell → Island → `IndicatorLayout` and/or the `services: ({...})` map consumed by
  `core/ModuleHost.qml`.
- Island states: `core/IslandState.qml` (island/minimal/module + `previousState` + `openCount`
  nonce so re-opening the same module replays the ContentSwap transition).
  Modules: `modules/<name>/XxxModule.qml` registered by name in `core/ModuleHost.qml`.
  Indicators: one file + entry (name/side/priority/source) in `indicators/Registry.qml` +
  one Loader in `core/IndicatorLayout.qml`; eviction by priority and island expansion
  (`extraWidth`) are computed there from each indicator's stable `desiredWidth`.
- Bar width is dynamic (no fixed `island.width`): `Island.barFittedWidth` fits the
  measured centered row in `IndicatorLayout` (spec order mic|music|dictation|
  clock|timer, nothing pinned to the edges — the clock shifts when an
  indicator grows, e.g. the mic hover label) with spacing/edgePad
  computed from the live content width, capped at `island.maxWidth`. Eviction is
  computed from stable desired widths against the shared budget (never from animated widths —
  that oscillates/deadlocks newcomers). Row children are vertically centered
  (pShell pattern) — without it short indicators top-align next to tall ones.
- Module islands are sized per module via `config.modules.<name>` (`notifications`
  splits into `notifications:flow`/`notifications:center` by payload mode);
  `island.moduleWidth/moduleHeight` is the fallback. Bar content is hidden
  (`opacity 0`) while the island is a bare Minimal strip — nothing renders inside it.
- Island lives on `WlrLayer.Overlay` (NOT Top): niri does not composite Top-layer surfaces
  above a fullscreen window, but Overlay stays visible. Required for the Minimal strip,
  tickers and modules opened from Minimal during fullscreen. Corners stay on Top.
- `core/GestureZones.qml` is declared BEFORE `islandRect` (below the bar content): a
  full-window MouseArea on top would swallow all indicator clicks/hover. Bar content
  gets priority; the gesture layer only sees presses on gaps/clock-text/outside zones.
- Recording is WM-agnostic: `compositor/Compositor.qml` keeps the spec'd
  `startRecording/stopRecording` API but delegates to `services/Recorder.qml` (single
  source of truth for the flag + wf-recorder process). Backends must NOT spawn wf-recorder.
  Compositor also needs `recorder: recorderService` injected in `core/Shell.qml`.
- The user runs BOTH niri and driftwm (check `pgrep -a driftwm` / `NIRI_SOCKET` before
  assuming). Drift backend: `driftwm msg subscribe --json` snapshots (`{"State":...}`),
  fullscreen = top-level `State.fullscreen[].output` (window `mode: "Fit"` is NOT
  fullscreen), no workspaces; protocol source in /usr/src/debug/driftwm/*/src/ipc/protocol.rs.
  Backends get `active` from Detect — only the detected one polls/subscribes.
- Compositor exposes per-screen state: `perScreen` map + `fullscreenOn(name)`/`workspaceOn(name)`
  with global fallback. Island uses `screen.name`. Niri backend polls `windows` + `workspaces`
  + `outputs`; this niri (26.04) has NO `is_fullscreen` in windows JSON, so fullscreen =
  `is_fullscreen === true` OR `window_size == logical output size` (±2px).
- `Process.signal(2)` sends SIGINT (pShell pattern); `terminate("SIGINT")` does NOT work —
  use `signal()` for graceful stops (see Dictation).
- ContentSwap commits content at the handover (after the blur-in stage): Island renders `shownModule`/
  `hostPayload` (set in `commitShownContent`), NOT `state.activeModule` — otherwise the
  new module pops in at full opacity before the fade. In-place updates (OSD repeat) set
  `state.activePayload` without reopening (no `openCount` bump, no swap).
- ALL content swaps go through `core/ContentSwap.qml` (two-stage blur→fade); all movement/size
  animation through `components/Spring.qml`. Never add linear/ease transitions or shaders.
  EXCEPTION (user decision): the side arcs' hide/show (`Arcs.hideProgress`) is a timed
  NumberAnimation (`arcs.hideMs`/`showMs`, InOutCubic / OutBack), not a spring. Sequence:
  bar holds its shape (`Island.arcsHold`) until the tuck reaches `arcs.collapseAt`, then
  collapses to Minimal; hiding arcs use the bar width frozen at hide time (horizontal) and
  the live island centre (vertical).
- Config: `config/config.json` watched by `config/Config.qml` (pragma Singleton, JsonAdapter,
  hot-reload). New tunable = add to BOTH the JsonAdapter defaults and config.json; read as
  `Config.data.<group>.<key>`. Pure visual tokens live in `services/Theme.qml`.
- Lock is shell-level, not an island module: `modules/lock/LockScope.qml` (WlSessionLock +
  `Pam.qml` + PAM config `assets/pam.d/pillshell`). Island hides while locked.
- IslandState: openModule over an already-open module must NOT overwrite `previousState`
  with "module" (closeModule would then re-enter a module-less "module" state → island
  stuck as an empty module-sized rect; `setIsland`/`setMinimal` refuse to leave "module").
  `core/IslandState.qml` guards both openModule (keeps the original pre-module state) and
  closeModule (falls back to island on a poisoned previousState).
- Fullscreen = Minimal until fullscreen ends (`minimalIdle` never lifts it). A swipe-down
  reveal under fullscreen stays while `islandHover` is hovered and drops back to Minimal
  `minimalIdleMs` after the cursor leaves (`fsRevealIdle`/`armFsReveal` in Island.qml);
  closing a module into the bar under fullscreen arms the same timer.
- MprisPlayer position reads are always live (Quickshell interpolates), but the
  positionChanged signal must be emitted manually while playing — the documented pattern
  (1s Timer, `onTriggered: player.positionChanged()`, running bound to Playing) is in
  `modules/player/PlayerModule.qml`. `length` mirrors `position` when `lengthSupported`
  is false — guard progress/remaining on that.
- Notification Center (`modules/notifications/center/`, Oct 2026, user decision over the
  spec's stripes): iOS-style list grouped by appName (newest group first; collapsed stack =
  front tile (red group counter on the avatar top-right, `NotificationCard.groupCount`) + `centerStackDepth` bottom-anchored plates, tap fans out under a header with
  «Свернуть»/✕; swiping a collapsed stack clears the group), swipe-left/✕ dismiss →
  `NotificationEntry.dismiss()`, tap → `invokeDefault()` (+dismiss, close) only if the sender
  has a "default" action. Wheel-only scroll (no Flickable). Tiles and the game deck GRAB
  presses, so each forwards swipe-up as `closeRequested` itself. Island height is
  content-fitted: module `preferredHeight` → `ModuleHost.preferredHeight` →
  `Island.centerFitHeight`, capped by `modules["notifications:center"].height`. While the center is open `Island.surfaceReserve`
  holds the layer surface at that cap (in-place morphs never resize the surface mid-spring),
  and every center spring uses the island's default `Spring {}` params — mismatched curves
  read as a two-phase "step" on group fan-out.
  Empty history = mini-game deck (`modules/notifications/games/`: GameDeck + DinoGame (port
  of dim-ghub/caelestia-shell `components/DinoGame.qml`, sprites in `assets/dino/`
  recoloured white) + FlappyGame; order `notifications.games`, horizontal swipe / [ ] / Tab
  switch, explicit Component registry in GameDeck). Island grants `keyboardFocus: OnDemand`
  while the center is open (click the game for Space/arrows). Last game + best scores live
  on the Notifications service (session only). Do NOT name game props `top`/`floor`-like
  Item members (`top` → "Cannot override FINAL property").
- MPRIS multi-player: `services/Players.qml` picks `active` dms-style (prefer a playing
  player, remember the last playing one, a paused player beats registered-idle ones at
  cold start). Plain `players[0]` picks early-registrants like Telegram (registers
  Stopped with stale voice-message metadata) over the actually playing app.

## Quickshell 0.3.1 / QML gotchas (hit before, verified)

- NEVER name an injected property the same as the `id` you pass it from at the
  call site. `Island { theme: theme }` inside `Shell.qml` is a self-reference:
  inside the object the property shadows the outer id, so it binds to itself
  (undefined forever). Source `id`s in `core/Shell.qml` are therefore suffixed
  (`themeService`, `audioService`, ...). Same trap for any property named like a
  type/attached name.
- NEVER declare `property ... screen` on a PanelWindow: it shadows
  `WindowInterface.screen` (qmllint `property-override`), the real window screen is
  never set and every per-screen window lands on one output. Use `targetScreen`.
- `Item`'s DEFAULT property is `data`. Declaring `required property var data`
  silently shadows it, so child items are dropped and the component renders
  empty. Use `payload` (see OsdModule/NotificationsModule).
- `QtObject` has NO default property: children like `Connections`/`Process`/`Timer`
  inside it fail with "Cannot assign to non-existent default property". Use
  `Scope` (import Quickshell) or hold them as `property X: X {}`.
- A binding that throws once (TypeError on undefined) is DISCARDED permanently →
  stale/default values (symptom: island rendered white). Bindings reading
  injected `var`/required props must be null-safe (`?.`, `??`).
- Grouped anchor properties cannot be animated: `Behavior on
  verticalCenterOffset` fails. Use a `Translate` transform with `Behavior on y`.
- `PwNode` has no `state` (only `PwLink` does). Mic-in-use = presence of capture
  stream nodes: `Pipewire.nodes.values` filtered by `isStream && !isSink && audio`.
- Imports: `IpcHandler`/`Process`/`FileView` need `Quickshell.Io`; session lock
  `Quickshell.Wayland`; players `Quickshell.Services.Mpris`; battery
  `UPower.devices`; bluetooth `Bluetooth.defaultAdapter`; apps
  `DesktopEntries.applications`.
- Island window height (`implicitHeight`) must follow `Island.paintBottom` = max(TARGET
  island bottom, ANIMATED `islandRect` bottom, `transitionLayer.flightBottom`). Sizing from
  the target alone shrinks the layer surface instantly on module close and crops the
  collapsing body and the shared element flying home (fixed Oct 2026). BUT never resize
  per frame (layer-shell resize = buffer realloc + compositor round-trip → freezes):
  `heldBottom` ratchets up (16px steps + headroom), holds while anything moves and
  shrinks once on `geometrySettled` — ~2 resizes per transition (verified Oct 2026).
- `IslandState.closeModule()` sets `currentState` BEFORE clearing `activeModule`: the
  reverse order briefly made the island target the fallback module size (560x210) on
  every close.
- Fullscreen decorative/large surfaces must set `mask: Region {}` (empty) or they
  swallow all input; keep PanelWindow heights tight around the island.
- Launcher needs keyboard: Island sets `WlrLayershell.keyboardFocus: OnDemand`
  only while the launcher module is open, else `None`.
- Avoid QML property names that collide with handler syntax (e.g. `on`).
- `openModule()` must set `activePayload` BEFORE `activeModule` — ModuleHost's
  Loader creates the module the moment `activeModule` changes and reads the
  payload at that instant.
- Module content must stay press-transparent (no fullscreen Flickable/MouseArea):
  swipe-up close is handled by `GestureZones` BELOW the island content, so any
  press-grabber covering the module makes it unclosable (hit with dashboard
  Flickable, Sep 2026). Only small controls (buttons/sliders) may accept presses.
- Quickshell's qml scanner sometimes MISSES a file's relative imports (no "Found imports"
  line and no "Synthesizing qmldir for <dir>" in the qslog) — then types from that dir
  fail at runtime with "X is not a type" even though qmllint is clean. If you add a new
  QML dir (or its only importer is a complex file), verify synthesis in the log; if
  missing, add the same import to a simple already-scanned file (e.g. `core/Shell.qml`)
  to force it. Known trigger undetermined (a Repeater-driven Registry version of
  IndicatorLayout broke it; explicit Loaders work) — bisect with smoke runs if hit.
- `Loader`-created items CANNOT use `required property` for things assigned in
  `onLoaded` (creation fails: "Required property X was not initialized"). Use plain
  properties with null-safe reads instead.
- Inside `Repeater` delegates prefer `modelData` over the Loader's `id` in outer
  bindings — delegate ids are not visible outside the delegate scope.
- Path elements (`PathMove`/`PathLine`, NOT `*To` — Qt6 names, live in QtQuick
  itself) inside `ShapePath` do NOT see the parent `Shape`'s own properties
  via scope lookup (`baseX is not defined`); qualify with an id or an outer id.
- MultiEffect `maskEnabled` is a HARD alpha threshold here (Qt 6.11, verified Oct 2026
  with an isolated sweep): a gradient maskSource stays binary, `maskSpreadAtMin` only
  shifts the cut (`min*(1+s)-s`). No soft alpha masks via MultiEffect — for soft edges
  over the opaque island paint background-colour gradients instead (`components/
  EdgeFade.qml`, used by ContentSwap: edge fade only while blur exists, strength =
  max(live blur, ghost opacity), width `effects.contentEdgeFade`).
  Rounded IMAGES therefore do not use a MultiEffect mask (stair-stepped corners):
  `components/RoundedImage.qml` is a `Shape` (CurveRenderer, `PathRectangle`)
  filled via `ShapePath.fillItem` from a layered wrapper around the Image
  (the layer bakes PreserveAspectCrop; a bare Image texture would not).
  The island's `clip: true` is RECTANGULAR: anything painted into its corners shows
  outside the rounding. ContentSwap therefore masks its layers (live, ghost, edge fade)
  to the rounded island shape (`surfaceRadius`, binary MultiEffect mask) while a
  transition runs.
- Canvas `shadow*` (`shadowColor`/`shadowBlur`/offsets) do NOTHING in Qt:
  the Context2D properties exist (assignments don't throw) but render no
  shadow (verified Sep 2026). Build glows from layered translucent strokes
  instead (see Arcs).

## Conventions (from pillShell.md)

- One file = one responsibility; ~200 lines is the split signal.
- No hardcoded sizes/thresholds — Config/Theme only.
- Indicators and modules never create windows; they live inside / extend the island.
- External tools: nmcli (wifi/hotspot), brightnessctl, grim+slurp (screenshots),
  wf-recorder (recording), pw-record (dictation capture).

## Working vs. stubbed (update as you go)

Working end-to-end (verified via IPC + screenshots + debugState, Sep 2026): bar island
(dynamic width fitted to content — clock-only ≈78px, expands with indicators, capped
at island.maxWidth with priority eviction; clock, arcs (concentric with the bar-end
rounding centres, no digits, grey track + bottom-up coloured fill, soft black halo) incl. bottom-up
battery fill, mic/music/dictation indicators, light halo around the body), per-module island sizes
(verified: dashboard 538×450, OSD 400×72, capture 520×112),
Minimal state (fullscreen-driven + IPC, per-screen), Overlay visibility over fullscreen,
modules launcher/quicksettings/dashboard/player/osd/capture/dictation/notifications
(center: iOS grouped list + mini-games when empty, verified via IPC + screenshots
(collapsed stack, expanded group, scroll cap 460, game deck idle) — taps/swipes/games
NOT live-tested; flow FIFO queue with 5s single / 3s queued lifetimes
(`flowShowMs`/`flowShowQueuedMs`) + collapse-to-bar gap between cards
(`flowSwapGapMs`, `pendingFlow` + `requeue` keep FIFO on user intervention),
verified headless on a nested bus with scaled timings, live D-Bus unreachable —
pShell owns the notification server; card layout `NotificationCard`: avatar (sender `image`, else app
icon, else initial letter) + app-icon badge on the avatar rim, title … time
(today HH:MM / Вчера, HH:MM / Пн HH:MM / dd.mm.yyyy), body, 3 lines max incl. title;
icon resolution chain: D-Bus app_icon → bare name smuggled via image-path
(notify-send 0.8.x) → `DesktopEntries` match by Name/id-suffix/exec in
`desktopIconFor` (Telegram Desktop sends empty app_icon; list populates async —
kicked on startup, first-seconds race accepted); incoming server objects are
marked `tracked` on receipt or `image://qsimage/…` avatars (image-data senders)
die with the notification;
history entries are live `services/NotificationEntry.qml` mirrors (Quickshell applies
`replaces_id` IN PLACE on the same Notification — no second onNotification), every
tracked object is released: sender close/expire → `closed` → `forget` (out of history,
`notificationClosed` → Island drops it from queue/pending/visible flow card), entries
past `historyLimit` are `expire()`d (verified on a nested bus via `dbus-run-session`:
replace in place, CloseNotification removes, 53 sent → 50 kept + 3 NotificationClosed);
`//@ pragma IconTheme` in shell.qml is REQUIRED for iconPath lookups (else the
provider's broken-image placeholder renders)), dashboard drawer (drag-follow + snap, code-complete),
dashboard cards (one file per card in `modules/dashboard/cards/` + shared
`DashboardCard`/`CardTitle`/`MiniBar`/`RingArc`; grid-first: fixed 1-unit
header block + 6x4 card grid (unit 80px, island 538x450); spans hardcoded
per card (system 2x2, wide 4x1, narrow 2x1), positions in `DashboardModule`,
widths locked via min=max=preferred (bare preferred loses to fillWidth
stretch + content minimums — grid splits evenly, system goes non-square),
content adapts (adaptive fonts/row counts); live: clock header RU, CPU/RAM/disk rings via
`services/SystemUsage`, battery, top processes, now-playing; weather card =
gradient by two continuous sun factors (daylight `d` = smoothstep ramp
ramped up at sr-45..sr+45 and down at ss-45..ss+45; horizon glow `w` =
smoothstep 60 min either side of sr/ss) over per-category Day/Night
palettes, warm #F29A5B mixed into the BOTTOM by 0.8*w*cloudDamp and dusk
violet #6C5B9E into the TOP by 0.25*w*cloudDamp (clouds eat the glow:
clear 1 / cloudy 0.5 / snow 0.4 / fog 0.35 / rain 0.3 / storm 0.15),
animated 900ms; no six discrete phases, no jumps) + emoji icon +
min/max,
via `services/Weather` open-meteo; pacman/AUR counts render empty state until
their slow first fetch lands; events = empty state, no calendar backend yet),
swipe-down
reveal from Minimal, swipe-up module close, mic exclusion of dictation/recording
(live: pw-record runs, no mic dot, wave expands island 420→448 and back), dictation
streaming (JSONL partial/final over stdout, `streamCommand` "stub"/custom/legacy-batch,
SIGINT flush (`signal(2)`), wtype-only typer with BackSpace rewrite, hallucination
filter, optional text finalizer + Gemma 4 E2B Refine via llama-server, `transcripts.jsonl`,
IPC start/stop/cancel/status + `dictation` block in debugState; real Nemotron 3.5 backend
wires in via `scripts/dictation/stream-nemotron.sh`; layout-followed language
(`services/KeyboardLayout`: drift subscribe / niri event-stream → `layout2lang`,
session restarts on layout switch when `followLayout`, mode `restart`;
pinned beats auto per the Nemotron card, but the layout must match the
spoken language — engine auto-detect is `followLayout: false` + `language:
"auto"`; backend `ready` (session.updated ack) flips the island from the grey
`switching` phase to live; Refine is rules → gate → LLM → validator
(deterministic filler/stutter cleanup, LLM only on correction shapes with a
`ruled` fast path (previewed in pending before commit), personal `corrections`
map for ASR confusions the deletion contract can't express; validator:
truncation/invented/provenance (per-word: exact or typo-close via
char-Levenshtein, replaces the length ratio)/over-deletion (drops >2 words
past half)/script-flip guards + thought/preamble strip; gate sees adjacent AND windowed (≤6w)
fuzzy repeats; prompt allows fusing split words / fixing 1-2-letter typos
against visible input words; eval harness in `scripts/dictation/eval/`
— 60 cases + run/score, needs a live llama-server; managed model lifecycle
(`refineServerCommand`: ensureModel on session start, /health poll till 200
with instant ruled fallback while warming, releaseModel (SIGTERM + 5s SIGKILL
watchdog) on session end — never on layout restart, respawn on unexpected
death; empty command = external server, no lifecycle);
server notes: static system prompt reuses KV-cache (`--cache-prompt` default
on), thinking stays OFF (no `<|think|>`, launch with `--reasoning off`;
Gemma 4 answers leak as `<|channel>thought…<channel|>` if it slips on), cap llama-server threads
(`-t`) to leave CPU headroom for Nemotron (`--device cpu`), cold start
(always-resident vs on-demand) undecided; index-deletion prompt (model
returns word indices to delete) is an untried alternative); the dictation wave is a real voice meter
(`PwNodePeakMonitor` on the default source, grey while switching,
auto-scaled: noise-floor gate (1.15x — peaks arrive cbrt-compressed) +
running maximum with a speech-level prior, so silence sits flat and any
mic swings full height; ready-guard on the source node, meter reseeds on
source change, 1s freeze watchdog bounces capture if peak sticks nonzero),
recording routed through the
Recorder service (single source of truth) incl. live red clock plate (elapsed timer,
island keeps bar size; stop returns the clock, wf-recorder reaped, file finalized), per-screen fullscreen/workspace, OSD only on
keys/IPC with auto-close, module→previousState (incl. back-to-Minimal from Minimal),
ext-session-lock + PAM, config hot-reload (all keys wired, no dead keys), startup
slide-in (appearFromEdge primitive: Minimal strip slides from top edge, then
morphs into the bar on its spot via `startupMorphDelayMs`; centered via anchor,
Y-only slide — no diagonal flight).

NOT live-tested (no mouse tool in this env — code-complete, needs manual drag/click):
presentation drag, minimal hold/reveal, dashboard drawer drag, side drags (QS/NotifCenter),
swipe-up close, music hover/click → player, clock-plate click → action buttons,
QS sliders/tiles, notification flow + ticker, lock screen visuals. Mic
indicator: exclusion list `config.audio.micExclude` (substring, hot-reload)
+ last-added stack display (verified headless via parecord fake clients +
debugState `mic` block: Telegram → +Discord → kill Discord → back).

Simplified / not implemented yet (see pillShell.md for the intended behaviour):
- Blur: backdrop blur via niri's `ext-background-effect-v1` is WIRED
  (`Region` pair + ping-pong kicks in Island.qml, pShell pattern — re-assigning
  the SAME region object is a compositor no-op; the region live-tracks the
  island through morphs (every geometry/state change re-kicks the current
  int-snapped shape, so the blur resizes together with the background
  instead of blinking; kicks are throttled to `timings.blurKickIntervalMs`
  (leading edge + trailing exact kick — per-frame effect reallocs stutter
  big morphs otherwise). Visible behind translucent
  surfaces: the Minimal strip (`minimalBg` + `minimalOpacity`) and any island
  area below full opacity (`effects.islandOpacity` < 1). Following the DMS
  approach the blur region is always exact-fit (no inset — tried Sep 2026,
  both a static and an opacity-driven animated inset: any inset merely moves
  the outside fringe into an inside seam once translucent): quickshell bakes
  Region radius into wl_region as an integer QRegion-ellipse staircase and
  niri (layer, no layer-rule → xray path, clip None, radius 0) blurs exactly
  that shape, so the ~1px divergence zone between the hard mask and the
  smooth painted corner is masked by a 1px rim over the island edge instead
  (`Theme.islandRim` + `islandRimWidth`), applied only while compositor blur
  is on (with `effects.disableCompositorBlur` the rim just lightens the true
  black edge, so `Island.qml` drops it to width 0). Region geometry is
  int-rounded first (fractional springs truncated outward + re-kicked on
  subpixel jitter otherwise). Deliberately NOT solved by staircase-painting
  the island to the mask (tried Sep 2026: needs output-scale plumbing,
  Qt renders the layer buffer at integer scale, exactness unverifiable). `components/BlurSurface.qml` is the in-window CONTENT blur (MultiEffect
  via `layer.effect`, `amount` 0..1, layer switched off at 0 so idle content is crisp and
  unlayered); `ContentSwap` drives it: swap = blur rises on old → handover (old frame
  frozen into a blurred ghost `ShaderEffectSource` live:false, owner switches content) →
  ghost fades out WHILE new fades in under blur → blur falls; ghost keeps its capture
  size (top-centred) so island resizes never stretch it; radius `effects.contentBlurMax`, off with `effects.disableBlur`
  (verified Oct 2026 with stretched timings in a scratch copy: bar clock blurs out,
  dashboard emerges blurred). No white wash anywhere: an 8% white overlay turned the
  true-black body #000000 into #141414 (Sep 2026).
  Island body is truly black (`Theme.islandBg #000000`, `effects.islandOpacity`
  1.0) except Minimal. Do NOT fake blur with a blurred wallpaper image —
  the island lives over app windows, wallpaper would mismatch.
- Capture: region selection delegates to `slurp`; the spec's dim+crosshair, flying square and
  second island instance are absent.
- (DONE Oct 2026) Shared element transitions: `core/TransitionLayer.qml` (top of the
  island window) lifts the owner's `sharedElement` (reparent, never recreated), flies it
  to the module slot `sharedSlot(key)` (ModuleHost resolver; slot = Item with
  `property Item docked`, module hides its own fallback while docked) tracking the
  slot's LIVE rect per frame (FrameAnimation — the island springs under it), lerps the
  contract `properties` (numbers/colours, `"slot"` = read from slot), lands with
  anchors.fill, and flies home on close/replace (`onActiveModuleChanged`), then calls
  `restoreShared()` to re-bind. Contract on the owner (`sharedTransition`: target, slot,
  properties, curve "spring" | Easing + duration). Trigger: `openModule(name,
  { shared: owner })`. Used by Music → player cover and ClockPlate → notification flow
  card "time" slot (clock text morphs to the card's text/colour/font, so it shows the
  ARRIVAL time; `sharedHome` = exact label box, `sharedHomeValues` = live clock values for
  the return; paths like "font.pixelSize", strings switch at p 0.5, start values are
  SNAPSHOTS — a colour read is a live value-type reference; a launch while the same
  element flies home turns it around in place). Verified with a fake MPRIS player
  (`dbus-run-session` + Gio script) and a timed 6s curve: out → landed (138px, r16) →
  home. `RoundedImage` keeps the last frame while re-decoding (`retainWhileLoading`)
  and decodes at power-of-two steps so the growing cover never blinks.
- `appearFromEdge` (startup / capture strip): startup slides the Minimal strip in
  from the top edge with a spring (`started` flag in Island.qml), then morphs it
  into the bar on its spot (`startupMorph` timer + `timings.startupMorphDelayMs`);
  the Capture second instance is absent.
- LocalSend is a placeholder drop zone (never opened); Timer indicator exists but no timer service feeds it.
- Player lyrics: the «Текст» pill in the player module is a visual placeholder (hover only,
  no action — user: a layout change/lyrics view comes later). Source decided by the user:
  lrclib.net via `curl -4` (the Weather fetch pattern, no API key) — plain + synced lyrics;
  pShell's caelestia C++ lyrics plugin is not portable (pure QML shell).
- Dictation layout-switch mode `dual` (hot ru+en sessions, zero-latency routing
  on layout switch) is PLANNED, not implemented: `config.dictation.switchMode`
  reserves the key, anything but `"restart"` warns and behaves as `"restart"`.
  Rationale: nemo-speech rejects `session.update` once audio started, so the
  language is per-session; dual needs a mic tee + per-stream routing.
