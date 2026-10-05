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
- Visual check: `grim /tmp/shot.png`, crop top-center. grim is fast here now (Oct 2026:
  ~60ms `-t ppm`, ~125ms png); earlier sessions saw ~1.9s — if so, raise
  `timings.osdAutoCloseMs` when screenshotting short-lived states.
- IPC: `quickshell -p $PWD ipc call <target> <fn>` (with the user's instance running,
  address yours via `quickshell ipc --id <by-id dir> call ...`). `island` is ONE handler
  (`core/IslandIpc.qml`) routed via `core/IslandRegistry.qml` to the island on
  `compositor.focusedOutput` — never put an IpcHandler in per-screen Island. Targets: `island` (launcher, quicksettings,
  notifications, capture (again while open = next mode), captureMode(shot|record|color|
  window|ai), captureScreen (= Enter in the active tool), captureCancel, screenshot
  (instant, no overlay), record (toggle), recordPause, recordControls, dashboard, player, lock, close, minimal, island, osd, debugState,
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
- Item built-ins shadow same-named JS functions: `function layer()` on an Item →
  "Property 'layer' ... is not a function" (it resolves to the `layer` group). Same for
  `state`, `data`, `children`, `visible`, ... — pick distinct names (`layerAt`).
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
- `components/RollingText.qml` = Apple numericText-style per-character drum
  roll (only changed chars roll, slots matched from the RIGHT via Row
  RightToLeft, auto direction: value up → roll UP, down → roll DOWN (user-corrected), Spring
  per slot, tabular digits via `font.features {"tnum": 1}`). Used by the
  system card metrics. Verified Oct 2026 with a slowed spring in a scratch
  FloatingWindow (`quickshell -p <dir>/shell.qml`, components symlinked).
- Canvas `shadow*` (`shadowColor`/`shadowBlur`/offsets) do NOTHING in Qt:
  the Context2D properties exist (assignments don't throw) but render no
  shadow (verified Sep 2026). Build glows from layered translucent strokes
  instead (see Arcs).

## Conventions (from pillShell.md)

- One file = one responsibility; ~200 lines is the split signal.
- No hardcoded sizes/thresholds — Config/Theme only.
- Indicators and modules never create windows; they live inside / extend the island.
- External tools: nmcli (wifi/hotspot), brightnessctl, grim (+magick crops, wl-copy,
  tesseract OCR, curl+jq Lens upload) for capture, wf-recorder + parecord + ffmpeg
  (recording), pw-record (dictation capture), uv (scripts/capture/*.py inline deps).

## Working vs. stubbed (update as you go)

Working end-to-end (verified via IPC + screenshots + debugState, Sep 2026): bar island
(dynamic width fitted to content — clock-only ≈78px, expands with indicators, capped
at island.maxWidth with priority eviction; clock, arcs (concentric with the bar-end
rounding centres, no digits, grey track + bottom-up coloured fill, soft black halo) incl. bottom-up
battery fill, mic/music/dictation indicators, light halo around the body), per-module island sizes
(verified: dashboard 538×450, OSD 400×72),
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
`DashboardCard`/`CardTitle`/`MiniBar`/`RingArc`; grid-first, iOS-widget look
(Oct 2026 redesign): thin header strip (time left | date right, shared
baseline, `dashboard.headerHeight`) + 8x3 grid (base unit 80px × `dashboard.scale` 1.25 → island 892x402; island size AND radius
are derived in `modules/dashboard/DashMetrics.js` (radius = cardRadius + margins, concentric —
user, Oct 2026), no `modules.dashboard` entry; cards scale literal px by `k`; user chose growing in width):
mixed shapes (user: a row of equal squares reads monotonous) —
`KKWWWWMM / KKSSBBMM / TTSSPPPP` (2x2 squares staggered across rows):
calendar 2x2 (iOS month, Monday-first, today on a red disc, no backend), weather 4x1 (always 1 unit tall, user), media 2x2
(blurred-cover backdrop via `RoundedImage.blur`, overscanned so rounded edges
stay solid; play/pause has PlayerModule's glyph-swap pop), system 2x2,
battery 2x1 (ring + laptop/bolt glyph), processes 4x1 (3 stat columns), sensors 2x1 (CPU °C heat-coloured by
`tempWarm`/`tempHot` + avg fan rpm + temp sparkline; `services/Sensors.qml`
discovers paths once — hwmon coretemp/k10temp + every `fan*_input` under
/sys/devices (T2 applesmc `APP0001` is NOT in /sys/class/hwmon) — and skips
amdgpu/nouveau/radeon: a sleeping dGPU answers EBUSY, never wake it). A
connections card (Wi-Fi/BT) was tried and rejected by the user. Tabler
codepoints: `uvx --from fonttools` + getBestCmap(). Cards are placed
with explicit x/y (`cellX`/`cellY`/`spanPx`), no GridLayout. Updates/Events
cards stay in cards/ but are off the grid (empty states only);
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
- (DONE Oct 2026) Capture = shell-level `modules/capture/` (CaptureScope in Shell, injected
  into Island as `capture`; NOT a normal module), full port of pShell's capture tools.
  Flow: `Island.openCapture(mode)` → `CaptureScope.begin()` grabs EVERY output first
  (`grim -t ppm`, one process, stamped `tempDir/src-<out>-<stamp>.ppm`) → overlays map
  (Overlay-layer PanelWindow per screen) → `island.startCaptureSteal()` opens the EMPTY
  `capture` module at the current size (`captureFrom`) so only the content blur->fades →
  `stealForCapture()` hands the global island rect to `capture.steal()`, hides the island
  via `contentItem` opacity (`stolen`, springs disabled so the reset jumps; never unmap)
  and replays appearFromEdge (= the spec's "second instance"). Grab-before-animation
  matters: the frozen frame must show the clean bar, not a mid-fade island.
  Overlay layers: `CaptureBackdrop` (frozen grab, drawn as 3 clipped pieces around a LIVE
  hole = `Island.captureHole()` band, so the steal + second instance stay visible) →
  `CaptureDim` (cut = tool's `cutRect`) → global crosshair → mode tool (Loader) →
  `CaptureSquare` (ContentSwap icon, glyph switches at the handover). Square/crosshair are
  ONE global state (`CaptureMotion`, global logical px) shifted per screen: size/radius
  springs to `squareSize`, flight = spring-driven quadratic bezier onto cursor+
  `chaseOffset` (`arcBend`), then chase springs (seamless: chaseX follows the target
  instantly while flying). Both hide while a selection exists.
  Tools (contract: `cutRect`, `dimmed`, `handleEscape()`, `handleKey(e)`, `confirm()`):
  `editor/RegionEditor` (shot/record/ai — flameshot editor split into EditorModel (rows +
  snapshot undo/redo), EditorInput (select/move/resize/draw/moveObj, wheel thickness, RMB
  palette; a plain click selects the highlighted smart region under the cursor, else
  the whole screen — pShell's click-always-fullscreen + dbl-click-only snap read as "auto
  select doesn't work" (user, Oct 2026)), SelectionFrame, EditorToolbar (ring layout), Annotation
  Item (10 tools; blur/pixelate sample a hidden full Image), PaletteRing, OcrPanel
  (tesseract on the pure grab crop, langs chips, re-crop on frame release), AudioChooser
  (record pending), EditorComposite (offscreen 1:1 physical composite → grabToImage →
  `out-<screen>.png` → deliver)); `color/ColorLoupe` + `ColorPanel` (pipette: 1×1 Canvas
  sampling, loupe = binary MultiEffect circle mask under a 2px ring, HSL sliders, formats,
  recent colours — memories are session-only on CaptureActions, never written to config);
  `window/WindowPicker` (rects from `compositor.windowRects(screen)`; click → selection
  preset for the editor). Window geometry: driftwm `position` = window CENTRE in canvas
  coords, output `camera` = viewport centre (verified vs grim); niri uses
  `tile_pos_in_workspace_view + window_offset_in_tile` (NOT live-tested). Mode "window"
  hides when no backend returns rects. A screen claims the session (`editScreen`) on the
  first selection/panel; only it keeps a tool and the Exclusive keyboard.
  Ordering trap (fixed): `confirm()` without a selection must ONLY select all (+commit in
  shot) — selecting triggers the mode follow-up (audio chips / OCR), confirming it in the
  same call started a recording without the audio choice.
  Also fixed (bug hunt Oct 2026, verified via IPC + debugState `toolSelection`/`smartRects`):
  shot/record/ai share ONE RegionEditor, so `switchMode` among them must keep the scope's
  `hasSelection` (resetting it desynced scope vs editor: crosshair/square back over the
  frame, Tab cycling) — the editor re-applies the follow-up on `onModeChanged`; the tool
  Loader stays alive through `closing` and fades with `dimLevel` (unloading dropped the
  selection cut → full-screen dim flash); a capture hotkey during the fade queues a NEW
  session (`queued`); toolbar hides Record while recording; RecordingActionsModule closes
  itself when recording stops elsewhere; no capture while locked; Enter ignored while OCR
  runs; smart regions cached per grab (`CaptureActions.smartCache`) — editors are rebuilt
  on every mode/screen switch.
  Cursor bubble (user, Oct 2026): pShell CursorGuide shape — `squareRadius` = full round,
  top-left `squareTipRadius` (Rectangle.topLeftRadius, Qt 6.7+; morphs from the island
  radius via `CaptureMotion.rTip`); shot mode glyph = scissors (eb1b). Toolbar buttons and
  the audio-chip bar are BORN from under the bubble: first appearance per selection snaps
  them to the bubble centre (`capture.motion`, springs/opacity disabled), then springs
  (`birthSpring`/`birthDamping`) to their slots while fading in; the bubble lingers
  `squareHideDelayMs` before fading so they visibly leave it. Tools are below the bubble
  in z (overlay order), that is what hides them at birth.
  Recording: `services/Recorder` runs `scripts/capture/record.sh` (pShell port): audio
  none|system|mic|both (null-sink mix + loopbacks), pause = segment split (SIGUSR1), live
  audio switch (`.audioctl` + SIGUSR2), discard, VAAPI via `recorder.hwDevice`.
  wf-recorder 0.6 HERE drops the video with `--audio` (pulse) and the audio with
  `--audio-backend=pipewire` — so record.sh captures video (wf-recorder) and audio
  (`parecord --latency-msec=50`; default latency loses ~2s of buffer on SIGINT)
  separately and muxes per segment (`-c:v copy -af apad -shortest`, silent track for
  "none" so concat stays compatible). All its PipeWire nodes are `pillshell_rec*` →
  ignored by the mic indicator. Island controls: `RecordingActionsModule` (timer, discard,
  audio cycle, pause, stop) on the red plate click / IPC recordControls.
  uv scripts (`regions.py` opencv smart regions, niri `nudge.py`) run via
  `CaptureActions.uvScript()` = `uv run --offline ... || uv run ...`: online `uv run
  --script` re-resolved deps on every start (~55s vs 1.6s offline).
  Verified on driftwm (IPC + debugState + screenshots): grab→steal→flight→chase, frozen
  backdrop + live hole, dim math (×0.65), shot commit 3/3 (PNG from the frozen grab, no
  overlay), AI → OCR panel, record → audio chips → recording (h264+aac, pause/stop via
  IPC), window highlight → editor preset, pipette loupe, recording controls render,
  record.sh modes none/system(+pause+switch to mic)/both standalone. NOT live-tested (no
  mouse/keyboard tool): drawing tools, text annotations, palette, toolbar clicks, resize
  handles, colour panel editing, OCR language chips, Lens upload, Esc chain, multi-monitor.
  Selections are per screen (pShell parity); only aim visuals span monitors.
  Buttons: `components/IconButton` (+ audio chips) carry a barely-visible white glow
  (`components/GlowRim`: 1px border rings OUTSIDE the shape, alpha falling smoothly;
  Theme `buttonGlow*`, peak 0.05 over 6px) so they read on dark content. User: a light
  haze, NOT a fill/wash and NOT an outline (0.2 alpha over 3px already read as a stroke);
  sizes from
  `capture.toolButtonSize/toolIconSize/toolRadius` (51/26/17 since the 1.5× bump).
- (DONE Oct 2026) Shared element transitions: `core/TransitionLayer.qml` (top of the
  island window) lifts the owner's `sharedElement` (reparent, never recreated), flies it
  to the module slot `sharedSlot(key)` (ModuleHost resolver; slot = Item with
  `property Item docked`, module hides its own fallback while docked) tracking the
  slot's LIVE rect per frame (FrameAnimation — the island springs under it), lerps the
  contract `properties` (numbers/colours, `"slot"` = read from slot), lands with
  anchors.fill, and flies home on close/replace (`onActiveModuleChanged`), then calls
  `restoreShared()` to re-bind. Contract on the owner (`sharedTransition`: target, slot,
  properties, curve "spring" | Easing + duration). Trigger: `openModule(name,
  { shared: owner })`. One element serving several modules declares
  `sharedTransitions: { <module>: contract }` (`TransitionLayer.contractFor`);
  ClockPlate → dashboard header time (`openDashboard()`, gesture + IPC) omits
  `text` from the contract so the docked label's live binding keeps ticking.
  A slot must be a WRAPPER Item: the guest docks as its child, so hide only
  the slot's own label inside (hiding the slot hides the guest too).
  Used by Music → player cover and ClockPlate → notification flow
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
  Capture reuses it for its second instance.
- LocalSend is a placeholder drop zone (never opened); Timer indicator exists but no timer service feeds it.
- Player backdrop: blurred album art fills the module (MediaCard pattern,
  `RoundedImage.blur` rounded to `island.radius` via `surfaceRadius` — island clip is
  rectangular) + horizontal dark scrim; controls use translucent white on top.
  Track change: backdrop and cover are `components/CrossfadeImage.qml` (two layers,
  one Spring driver; cover pops 0.85→1 over the old one shrinking, backdrop fades
  in over an opaque old frame — `exitFade: false`, no scale >1 on clipped surfaces).
- Player lyrics: the «Текст» pill in the player module is a visual placeholder (hover only,
  no action — user: a layout change/lyrics view comes later). Source decided by the user:
  lrclib.net via `curl -4` (the Weather fetch pattern, no API key) — plain + synced lyrics;
  pShell's caelestia C++ lyrics plugin is not portable (pure QML shell).
- Dictation layout-switch mode `dual` (hot ru+en sessions, zero-latency routing
  on layout switch) is PLANNED, not implemented: `config.dictation.switchMode`
  reserves the key, anything but `"restart"` warns and behaves as `"restart"`.
  Rationale: nemo-speech rejects `session.update` once audio started, so the
  language is per-session; dual needs a mic tee + per-stream routing.
