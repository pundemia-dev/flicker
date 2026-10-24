# AGENTS.md

## What this repo is

Flicker — a Wayland desktop shell on Quickshell (pure QML, no C++/build step): a single
"Dynamic Island" per monitor instead of a bar. The authoritative spec (Russian) is
`flicker.md` — read the relevant section before implementing any feature/gesture/animation.
Reference implementation: `~/.config/quickshell/pShell` (also see its `CLAUDE.md` and
`docs/development/`). Per spec: check how pShell does something before writing an equivalent.

No tests, no linter, no formatter. Machine-specific notes (hardware, the dev box, the
user's data) live outside the repo: `CLAUDE.local.md` (git-ignored) and `~/.claude/CLAUDE.md`.

## Run / verify

- Entry file MUST be `shell.qml` (Quickshell 0.3.1 loads `shell.qml`, ignores `main.qml`).
  Current content: `import "core"` + `Shell {}`.
- Smoke test: `timeout 8 quickshell -p $PWD 2>&1 | head -40` (needs a Wayland session).
- Runtime logs: stderr and `$XDG_RUNTIME_DIR/quickshell/by-id/<id>/log.qslog`.
- Next to another shell these warnings are EXPECTED and harmless: "Could not register
  notification server at org.freedesktop.Notifications", portal "Connection already
  associated with an application ID".
- NEVER leave a background Flicker running next to a live `qs -c flicker`: two same-config
  instances overlap on screen (looks like mismatched radii!) and IPC routing between them
  is ambiguous. Before starting one, check BOTH forms: `pgrep -af "quickshell|qs -c"`.
  Kill yours immediately after (`kill <PID>`, literal PID — `pkill -f`/subshell kills are blocked).
- Real pointer input: `python3 temp/vmouse.py <dx dy>... click sleep <s>` = uinput virtual
  mouse (needs a writable /dev/uinput), clicks/moves land through the compositor
  like a real mouse. Move in SMALL steps (`-40 0` ×20): one large relative jump barely moves
  the cursor. Cursor position: debugState `capture.square` while capture is open.
- Visual check: `grim /tmp/shot.png`, crop top-center. If grim is slow (~1.9 s seen), raise
  `timings.osdAutoCloseMs` when screenshotting short-lived states.
- IPC: `quickshell -p $PWD ipc call <target> <fn>` (with a live instance running,
  address yours via `quickshell ipc --id <by-id dir> call ...`). `island` is ONE handler
  (`core/IslandIpc.qml`) routed via `core/IslandRegistry.qml` to the island on
  `compositor.focusedOutput` — never put an IpcHandler in per-screen Island. Targets: `island` (launcher (toggle), launcherPlugin <id> (apps|clipboard|wallpapers, toggle), quicksettings, quicksettingsEdit/Page/Resize/Expand, quicksettingsPanel <cmd> <arg>, stashMenu <i>,
  notifications, stash (tray toggle), capture (again while open = next mode), captureMode(shot|record|color|
  window|ai|scan), captureScreen (= Enter in the active tool), captureCancel, session (session menu toggle), screenshot
  (instant, no overlay), record (toggle), recordPause, recordControls, dashboard, dashboardEdit, dashboardResize, dashboardMove, player, lyrics (player's lyrics panel toggle), updates (toggle), lock, close, minimal, island, osd, debugState,
  volumeUp/Down/Mute, micMute, brightnessUp/Down, playPause, nextTrack, prevTrack, playerSeek <s>),
  `island powerSave` (Low Power Mode toggle), `island airplane` (Airplane Mode toggle), `island vpn` (VPN on/off, see VPN below), `lock` (activate/isLocked — deliberately NO unlock/toggle over IPC; unlocking needs PAM),
  keyboardDemo layout|caps, touchBarDemo <x 0..1> <ms>, shazam (listen / cancel), timer (module toggle), timerStart <min>, timerPause (toggle), timerCancel, stashTranscript <path>, stashPreview <path>,
  statusDemo <name> <percent> (<0 = spinning) / statusDemoEnd <name> / statusNext (= swipe on the drop),
  `dictation` (start/stop/toggle/cancel/status),
  `settings` (open / section <id> / close / toggle — the settings window, section ids in
  `modules/settings/SettingsSchema.js`),
  `prompter` (open <path>, clipboard, text <s>, show/close/toggle, pause, mode voice|auto|manual,
  move <n words>, next/prev (block), status).

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
  measured centered row in `IndicatorLayout` (order timer|privacy|music|dictation|
  clock, event halves pinned to the island edges outside the row, nothing else pinned — the clock shifts when an
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
- Both niri and driftwm are supported (check `pgrep -a driftwm` / `NIRI_SOCKET` before
  assuming). Drift backend: `driftwm msg subscribe --json` snapshots (`{"State":...}`),
  fullscreen = top-level `State.fullscreen[].output` (window `mode: "Fit"` is NOT
  fullscreen), no workspaces; protocol source in /usr/src/debug/driftwm/*/src/ipc/protocol.rs.
  Backends get `active` from Detect — only the detected one polls/subscribes.
  Hyprland backend: `hyprctl -j monitors/workspaces/clients`, refreshed on any `.socket2.sock`
  event (debounced) + poll every 2×`pollMs` (drag/resize emits no event); fullscreen = client
  `fullscreen` 2/3 (1 = maximized). KeyboardLayout: `hyprctl -j devices` main keyboard +
  `activelayout>>KB,LAYOUT` (full XKB names). Verified in a nested Hyprland 0.56 (Oct 2026).
- Compositor exposes per-screen state: `perScreen` map + `fullscreenOn(name)`/`workspaceOn(name)`
  with global fallback. Island uses `screen.name`. Niri backend polls `windows` + `workspaces`
  + `outputs`; this niri (26.04) has NO `is_fullscreen` in windows JSON, so fullscreen =
  `is_fullscreen === true` OR `window_size == logical output size` (±2px).
- OSD (`modules/osd/OsdModule.qml`, iOS-style, Oct 2026) is CHANGE-driven, not key-driven:
  `core/OsdWatcher.qml` (caelestia/DMS pattern) shows it on ANY volume/mute/brightness
  change, so compositor binds run `wpctl`/`brightnessctl` directly and keep working with
  the shell down (driftwm 0.19 binds the XF86 keys to exactly that by default). Own UI
  changes are skipped via the service's `osdQuietUntil` (`audio.quiet()` /
  `brightness.quiet()` before a QS slider set — spec: no OSD from Quick Settings); a
  default sink/source switch and start-up (`osd.startupQuietMs`) are quiet too. External
  brightness = inotify `FileView` on `/sys/class/<class>/<dev>/brightness` (VFS writes
  raise IN_MODIFY on sysfs, verified; noctalia approach). The module binds LIVE service
  values (PipeWire applies volume async); IPC keys only add `push` ±1 when a press hits
  an end (no change signal) → bar rubber-bands. Layout = pShell BatteryTank turned
  horizontal: island 340×60 r20 (user), one big `RoundedClip` capsule (inset `osd.inset`,
  concentric radius), fill + track split by `osd.gap` with `osd.innerRadius` inner edges, glyph left + number right INSIDE, drawn twice
  (light ink over the track, dark ink clipped to the fill). Tunables `Config.data.osd`. `services/Audio.qml` must keep sink/source in its
  `PwObjectTracker` — untracked nodes never turn `ready`, setVolume was a silent no-op.
  Reference shells cloned in `temp/` (caelestia, DMS, end-4 dots, noctalia (now C++)).
- Touch Bar press tabs (Oct 2026, Macs with tiny-dfr ONLY — no F-key/other-laptop path by
  user decision): `scripts/touchbar/presses.py` reads tiny-dfr's uinput device ("Dynamic
  Function Row Virtual Input Device", never grabbed, never the main keyboard) and lays the
  buttons out exactly like tiny-dfr `FunctionLayer::draw` (16 px gaps, Stretch, empty slots,
  "esc" prepended only when the bar is >= 2170 px — this MBP16 bar is 2008 = no esc, read from
  the `card*-USB-*` DRM mode), re-reading `/etc/tiny-dfr/config.toml` on mtime change
  (dfr-switcher layouts). It prints only `down <id> <x> <w>` / `up <id>` / `reset` (bar
  fractions) — key codes stay inside. `services/TouchBar.qml` → ListModel → per-screen
  `core/TouchBarPresses.qml` (Overlay, empty mask, built-in display by default): CurveRenderer
  PathSvg tab joined to the edge by concave Bézier suction curves (spread / rise / strength) and a convex quarter ellipse (`radius` along the top, the rest of the height up) from the suction straight into the top edge in `corners.color`, SpringAnimation on height.
  Access = `scripts/touchbar/udev.rules` (uaccess); without it the script waits and logs the
  sudo hint once. Config `touchBar` (width/height/widthMode/span/offset in Settings → Keyboard).
- Trackpad haptics (Oct 2026), hardware-agnostic — full contract in `docs/haptics.md`:
  `services/Haptics.qml` (Shell → Island → services map, ControlCenter, OsdWatcher) runs
  `scripts/haptics/run.py` (dispatcher: `backend: "auto"` probes `order`, or a name, or a
  path; exec()s the winner) and writes `<effect> <intensity 0..1>` lines to its stdin.
  Effects: click/deep/release/tick only (tick = OSD value marks). Backends = `scripts/haptics/backends/<name>/backend`
  (`probe` exit 0 usable / 1 none / 2 no access + hint; `run --options JSON`) + `udev.rules`:
  `evdev-haptic` (kernel FF_HAPTIC, never FF_RUMBLE = gamepads; ctypes structs verified
  48 B / EVIOCSFF 0x40304580, NOT tested on hardware), `apple-t2` (hidraw report 0x53,
  verified on hardware; release = the driver's segment-less packet `53 01 s f`
  (`rate_probe.py release-native`: 14/90, 28/ff, 14/ff, click→release at 0 ms all pass), tick =
  click waveform; after a FAILED RESUME FROM SUSPEND the T2 may reject anything), `_template`. A change of backend/order/backendOptions restarts the backend (`setupKey`).
  Exit 3 = no backend → re-probe every `rescanMs`
  with `--quiet` (hint logged once). apple-t2: NEVER send untested bytes — a rejected
  packet stalls EP0 of the whole keyboard/trackpad and the T2 resets it (~5 s, hidraw
  renumbers; GET_FEATURE 0xBB on input0 also stalls) — NOT always: a stall can stay wedged
  (timeouts, no reset) → only a REBOOT recovers it. Cause found with
  `temp/haptic/rate_probe.py` (log `temp/haptic/logs/rate-probe.jsonl`): NOT bytes, NOT rate (a
  write blocks ~5 ms; 0 ms gaps, 1000-write floods, Caps Lock LED / backlight toggles all pass;
  the segment-less release packet is fine too) — TWO CONCURRENT WRITERS race on the shared EP0
  and stall it (probe "parallel": 1 of ~45 overlapping pairs; first seen with a smoke instance
  next to a live shell). So the backend holds an exclusive flock on the device (second writer stays
  silent, logs once) — NEVER run a second Flicker with haptics on. After EPIPE/ETIMEDOUT it
  goes quiet until the HID node re-enumerates (logs effect/packet/gap); minIntervalMs 40 (rate is irrelevant) (toggling the USB device's
  `authorized` 0/1 was tried: keyboard+trackpad never came back, Oct 2026); plain write() of the exact packet
  length = EP0 SET_REPORT (no OUT endpoint). Test packets against a plain file
  (`--options '{"device":"/tmp/f"}'`, xxd). Places (user decision, `Config.haptics`
  toggles): BOUND volume/brightness reaching/passing a multiple of `osdStepEvery` % (10; settings
  window Haptics → Where) = tick (OsdWatcher; QS sliders are quiet →
  silent); QS edit entry = deep, layout snap during drag-move =
  click, tab switch / resize snap = release (ControlCenter.setPage/beginEdit/setPreview); QS slider reaching 0/100 and SeekBar
  crossing an end = release; wallpaper carousel = click per card passing the centre
  (`haptics.wallpapers`; recording speed ruler = click per value passing the centre while scrolled /
  dragged, `haptics.recordSpeed`, haptics reach plugins via `LauncherPlugin.host.haptics`). Explicitly NOT wanted: GestureZones swipes, dashboard drawer
  threshold, notification swipe, QS tab rubber band. Probe/CLI tools in `temp/haptic/`.
- Lyrics (Oct 2026): `services/Lyrics.qml` is owned by Players (`players.lyrics`, no Shell
  wiring) and runs `scripts/lyrics/fetch.py` (`lyrics.sources`: local .lrc next to the file →
  lrclib → NetEase (synced) → Genius (plain, last resort); synced beats plain; urllib forced to
  IPv4; name variants split "A/B" artist tags and drop (…) title tails; cache incl. misses in
  `cachePath("lyrics")`). Musixmatch was tried: its anonymous token (`000000…`) only returns a
  fixed placeholder track — unusable without a real user token; Yandex Music answers 451. `lyrics.shown` widens the player island by `lyrics.panelWidth`
  (Island moduleSize); the player part keeps `modules.player.width`. `LyricsView`: springs only,
  tap = seek via TapHandler (passive grab — swipe-up close still works), edge fade is per-line
  opacity (MultiEffect masks are binary here). Config group `lyrics`.
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
- Settings window (`modules/settings/`, Oct 2026, user design: iOS tiles / large title /
  search / grouped inset lists / drill-down + end-4 nav rail, content card, config-file
  button; NOT macOS). The ONE ordinary app window of the shell (`FloatingWindow` =
  xdg-toplevel, the WM places / tiles / closes it), lazily created by `SettingsScope` in
  Shell. Content = `SettingsSchema.js`: module BEHAVIOUR only (user: no paddings / radii /
  springs there; but anything about a module's behaviour that can annoy must be there).
  Writes go through `Config.set(path, value)`: the adapter group is replaced live and the
  pending paths are PATCHED into config.json's own text after 300 ms (`writeAdapter()`
  sorts every key — never use it); our own write's change event is not re-read.
  Wallpaper rows use the carousel panel's rows + overrides (`store: "wallpaper"`).
  Pages are created on push and destroyed on pop (springs); a section switch = blur-fade.
- Config: `config/config.json` watched by `config/Config.qml` (pragma Singleton, JsonAdapter,
  hot-reload). New tunable = add to BOTH the JsonAdapter defaults and config.json; read as
  `Config.data.<group>.<key>`. Pure visual tokens live in `services/Theme.qml`.
- Lock is shell-level, not an island module: `modules/lock/LockScope.qml` (WlSessionLock +
  `Pam.qml` + PAM config `assets/pam.d/flicker`). Island hides while locked.
  Lock-in / unlock animation (user design, Oct 2026): `activate()` grabs every output FIRST
  (grim PPM → `$XDG_RUNTIME_DIR/flicker/lock`, 700, deleted on unlock; `grabTimeoutMs` /
  failure → lock anyway, from black), THEN locks — the surface's first frame is the grab (no
  seam; driftwm shows a blank Pending frame until our first commit). `LockBackdrop` runs
  `scripts/lock/regions.sh` (wallpaper wallr shows on that output — the fill-blur composite
  itself — + `diff.py`: grid diff vs the cover-fitted wallpaper, row-run union-find boxes,
  ~0.25 s) and every region that differs (windows, island, notifications) dissolves as a
  `LockTile` (ShaderEffectSource crop of the base grab → blur then fade), LARGEST first,
  one after another with an overlap (`overlapIn`/`overlapOut` of a step, `gapMs`; the chain is capped by `sequenceMaxMs` — steps shorten), wallpaper showing through; base grab fades under them. TIMED, not springs
  (user exception: smoother into / out of the blur) — `dissolveMs`/`returnMs`, `easing` = Easing name. GIF/video wallpaper
  (user): `regions.sh` extracts the frame wallr showed (ffmpeg, like the carousel thumbs) — a video
  at the position `wallrctl.sh pos` read TOGETHER with the grab (`<grab>.pos`, written by the
  LockScope grab command), a GIF's first frame (no GIF position in wallr) — into `<grab>-wall.jpg`
  and reports it as a still image, so the normal pixel diff + dissolve applies (~150 ms extra). No
  frame → kind stays moving → `diff.py --no-diff` (inpaint only) and one screen-wide tile that only
  blurs. No wallpaper → the same blur. Tried and DROPPED (Oct 2026): a playing copy of the video /
  GIF on the lock synced to wallr (live position via `wallr ipc info`, GIF clock + wallr's frame
  delays) and wallr paused for the lock with a resume/revive + seek hand-back — wallr's picture can't
  advance under the lock, so its catch-up after unlock always showed (fast forward), and IPC that
  renders (set) stalls while locked. Unlock = exact reverse (smallest back first),
  then `finishUnlock()` — the live desktop may differ from the grab (user accepted the jump).
  Tunables `Config.lock`. Verified in a scratch overlay harness (PanelWindow + fake scope,
  grim frames): regions match the windows, wallpaper vs grab outside regions < 1/255. NOT
  tested in a real session lock (needs the password): first-frame seam, multi-output.
  Placeholder clock/dots in `LockSkin` until the real lock UI.
  Password field = the ISLAND's copy (`LockField`, user): `LockScope.activate()` snapshots every
  island's `lockRect()` (Island.qml, screen-local islandRect; Shell injects `registry`) BEFORE the
  grab; the field starts exactly there showing the RAW grab's crop of it (+ `holeMarginPx`, so the
  side arcs come along) — no seam; on dissolve start the crop blur-fades, then (`fieldDelayMs`)
  the black body flies on springs into `fieldSlot` (column placeholder under the date), dots /
  "Enter Password" blur in; wrong password = under-damped `kick()`. Unlock: flies home, crop
  returns, `arrivedHome`; the skin finishes when BOTH that and the backdrop reverse are done
  (~0.8 s measured). The grab's own island is painted out by `diff.py --hole` (strip below it
  stretched + Gaussian) into `<grab>-inpaint.ppm`, which the BASE (= tile texture) switches to —
  a QML inpaint item nested inside the tiles' ShaderEffectSource source did NOT reach the tiles
  on the way back (old island reappeared), and a wallpaper patch read as a light block over a
  dark window. Starting from Minimal works too (verified: strip → field → strip). Timing
  measurements with `grabToImage` frames lie (5.9 s vs 0.8 s) — use grim for frames.
  Password dots (`LockDots`, user: like caelestia's MaterialShape input): each char pops in as a
  random shape and morphs into the dot; a deleted slot shrinks away (a ListModel trails the count
  by `dotExitMs`, appended/removed at the end — an INT Repeater model rebuilt every delegate, so
  all dots replayed the pop-in on each keystroke). M3Shapes (C++ plugin, not packaged) is NOT
  used: `components/MorphShape.js` = polar r(θ) shapes (cookie/sunny/burst/star/n-gon, max r 1),
  morph = per-angle lerp; `components/MorphDot.qml` = CurveRenderer PathPolyline of it. Verified
  with harness frames (shapes, morph, collapse).
  Lock clock = flown out of the bar clock (`LockClock`, user): `Island.lockClock()` (part of
  lockRect: ClockPlate `sharedHome` box + label font, only while the bar shows) → drawn at
  `clockFontSize`, scaled to the bar size, crossfades with the field's bar crop on the spot, then
  centre + scale spring to `clockSlot` (invisible same-font Text in the column); bar weight until
  half way, then Light; no home (Minimal / module) = just blur-fades in at the slot. Unlock waits
  for it too (`clockHome`). Time from Quickshell SystemClock ("hh:mm" like services/Clock).
  Verified with grim frames in the harness. Wrong-password lag = failure delays of BOTH pam_unix
  and pam_faillock (1.5.x+ has its own) → `nodelay` on every line of assets/pam.d/flicker
  (measured 1.9 s → 4 ms with a PamContext for user `nobody` — Quickshell refuses unknown users,
  and `nobody` never touches the real user's faillock tally).
  Keyboard pill on the lock (`LockKeyboardPill`, user): the session lock hides KeyboardOverlay,
  so the skin draws the same `KeyboardPill` `keyboard.lockGap` under the password field's CARET
  (`LockField.caretX` = just past the last dot, `caretGap`; centre while empty — it follows the
  dot row): Caps Lock for as long as it is on, a layout switch while `KeyboardIndicator.
  flashing`; no pointer probe. driftwm sends subscribe snapshots
  only after a RENDERED frame, so a layout switch on the static lock arrived late or not at all
  ("not always shown") → the skin calls `KeyboardLayout.poll()` (re-reads `driftwm msg --json
  state`) 20 ms after every key without text. Shell injects `keyboard` + `theme` into LockScope; the column keeps
  a spacer under `fieldSlot` so the status line sits below the pill. Verified in the harness.
  wallr playback state = `services/WallrClock` (child of Wallpaper, `Wallpaper.clock`): per-output
  pause (fullscreen — incl. a window exactly the output size, drift `coversOutput` — / battery);
  ONE Process per output runs the commands in order, only the one needed to reach `want` (`applied`
  unknown|paused|playing): separate pause/resume processes raced (pause + position read is slower,
  so a quick fullscreen toggle left a GIF paused) and a command sent while one ran was dropped.
  Every wallr call through `scripts/wallpapers/wallrctl.sh` (pos /
  pause→pos / resume [revive] [seek] / resync; never seek while paused — corrupts wallr's pause
  bookkeeping; positions only in `wallr ipc info` text "State: playing @ 71.62s"); a revive after a
  long pause seeks back to the frozen position; at shell start every output is revived in place
  (`resume here 1`) — a plain resume killed a wallr left paused > 5 s by an earlier shell (every hot
  reload did). Lock: wallr plays on but falls behind (surface hidden → Vulkan FIFO present blocks;
  sampled) and after unlock played the missed frames through (~4 s fast forward after a 2 min lock);
  a plain seek right at unlock KILLED it (loop wakes to a flushed decoder, last upload > 5 s old) →
  `lockEnded()` runs `wallrctl.sh resync` (re-set the video + seek to its own clock + re-set time).
  Same trap anywhere wallr is HIDDEN while it seeks/re-sets: a test overlay covering the screen
  plus a second WallrClock (its start-up revive) killed it — never instantiate WallrClock in harnesses.
  Sampled after a real lock + resync: wallr decoding again at once.
  Avatar shadow = stacked translucent rings outside the circle (`avatarShadow*`; 0.05 picked on a
  flat-grey comparison); its FadeBlur is larger by `shadowMargin` inside an avatar-sized slot (a
  layer the avatar's size cut the shadow while fading). Avatar `LockAvatar` (top of the placeholder column, above the clock, 384 px; own FadeBlur that
  waits for `settled` = media decoded / none / `avatarWaitMs`): still image / GIF·WebP·APNG
  (AnimatedImage) / video (MediaPlayer, no audioOutput = silent, looped) — kind by MIME via
  `scripts/lock/avatar.sh` (`lock.avatar` "" = ~/.face → ~/.face.icon → AccountsService;
  ~/.face has no extension); RoundedImage-style circle (CurveRenderer Shape, fillItem = hidden
  layered wrapper — GIF/video frames update through it); fallback = initial on a disc.
  Verified in a scratch PanelWindow (grabToImage ×2: GIF + video frames change).
- IslandState: openModule over an already-open module must NOT overwrite `previousState`
  with "module" (closeModule would then re-enter a module-less "module" state → island
  stuck as an empty module-sized rect; `setIsland`/`setMinimal` refuse to leave "module").
  `core/IslandState.qml` guards both openModule (keeps the original pre-module state) and
  closeModule (falls back to island on a poisoned previousState).
- Fullscreen = Minimal until fullscreen ends (`minimalIdle` never lifts it). A swipe-down
  reveal under fullscreen stays while `islandHover` is hovered and drops back to Minimal
  `minimalIdleMs` after the cursor leaves (`fsRevealIdle`/`armFsReveal` in Island.qml);
  closing a module into the bar under fullscreen arms the same timer.
  Notification in Minimal / fullscreen = TICKER (`core/NotificationTicker.qml`, Oct 2026, user):
  the bar WIDENS by `tickerReserve` on the left (in `barFittedWidth` + IndicatorLayout
  `extraReserve` eviction budget; the row moves right on `tickerShift`, same spring as the
  island width) — never drawn over the clock. Sender avatar / app icon (letter fallback) at the
  bar music cover size (`indicators.musicCoverDiameter`) stands still, text (summary + body)
  in a viewport fitted to it up to `notifications.tickerWidth`; longer text loops at
  `tickerSpeed` px/s, and `tickerTimer` follows `showMs` (≥ one pass). Verified live with
  notify-send + grim frames.
  NEW INDICATOR in Minimal = PEEK (`core/IndicatorPeek.qml`, Oct 2026, user): any row indicator,
  event or status event turning on while Minimal first unfolds the bar WITHOUT it (IndicatorLayout
  `holdNew` + `known` snapshot; `activeKey` = raw active names, both event halves = "event"), the
  newcomer shows after `indicators.peekRevealMs`, the bar stays `peekShowMs` (event / hover hold it,
  then `peekTailMs`) and folds back. `barShowing` counts the peek (status drop splits off in it).
  Not while a module / capture / start-up (things that came on meanwhile count as known); ticker or
  hold reveal = already revealed, no hold. `peekIgnore` names never peek (music play/pause in a
  fullscreen video peeks otherwise). Verified live (eventDemo pacman, statusDemo + grim frames).
- MprisPlayer position reads are always live (Quickshell interpolates), but the
  positionChanged signal must be emitted manually while playing — the documented pattern
  (1s Timer, `onTriggered: player.positionChanged()`, running bound to Playing) is in
  `modules/player/PlayerModule.qml`. `length` mirrors `position` when `lengthSupported`
  is false — guard progress/remaining on that.
  Seeking: `MprisPlayer.position` is WRITABLE (needs `canSeek && positionSupported`) —
  `modules/player/SeekBar.qml` (player module + QS media card) scrubs a local position,
  seeks once on release, holds the target until the player reports it (no snap-back).
  Past an end the bar rubber-bands toward the pull (OSD look: longer + thinner,
  `Config.seekBar` stretch = max·o/(o+softness), springs back on release).
  Verified the write via IPC `playerSeek` on G4Music; mouse scrubbing NOT live-tested.
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
- Notification actions (Oct 2026): server advertises `actions` + `inline-reply` (senders like
  Telegram read capabilities at THEIR start — restart them). Tap (flow card + center tile) =
  `Notifications.open(entry)`: default action, then focus the app's window via
  `services/AppActivator.qml` (Quickshell `ToplevelManager` = wlr-foreign-toplevel, served by
  niri AND driftwm; match desktop-entry hint / appName / .desktop id/startupClass/exec,
  retried a few times after a default action), else launch the .desktop entry
  (`launcher.apps.launchPrefix`); then dismiss. Flow card = `modules/notifications/FlowCard.qml`
  (grabs presses, forwards swipe-up close): drag down = island follows (preferredHeight →
  Island moduleSize for `notifications:flow`, `surfaceReserve` holds the max), snaps open past
  `flowPullThreshold` → context buttons (sender actions, Reply, Dismiss); long press
  (`flowLongPressMs`) = inline reply field (`Notification.sendInlineReply`, Exclusive keyboard
  via `ModuleHost.wantsKeyboard`; no reply support → buttons). `ModuleHost.holdOpen` pauses
  `flowAutoClose` and `shortenFlow`. ModuleHost `closeRequested` now only closes when the
  requesting module is the active one (tap + sender close fired two closes). Verified with
  temp/vmouse + wtype + dbus-monitor: drag → buttons, long press → field, Enter →
  NotificationReplied, tap → ActionInvoked default, swipe up closes. NOT verified: window
  focusing visually, launch path. The panel (label-fitted centred pills / reply field) is
  `modules/notifications/NotificationActions.qml`, shared with the center: SwipeCard
  (`actionable` = not a collapsed stack) grows by `extraHeight`, NotificationGroup lays tiles out
  by the sum, NotificationCenter owns ONE open panel (`actionEntry/actionStage`, `wantsKeyboard`);
  an action / reply there collapses the tile (center stays open). Center panel NOT live-tested.
- Notification policy (Oct 2026, user: rules / DND / privacy like DMS, Noctalia, swaync): ONE
  decision per arrival in `Notifications.policyFor` → `entry.policy` {toast, sound, history,
  bypassDnd, durationMs}; Island only gets toasts (`onlyUrgentToast` moved out of Island).
  Rules = `notifications.rules` (first live match wins; regex app = appName|desktopEntry, text =
  summary|body; flags only take away, but bypassDnd/durationMs), edited in settings
  (`SettingsNotifs.js`, store "notifRule", refs `{index, id, list}`: rules carry a stable `id`
  (`ensureRuleIds` adds missing ones) and pages resolve by it (`SettingsWindow.refIndex`) since
  mute / sweep reorder the list under an open page; the VPN rule actions
  ruleUp/Down/Delete/pageClosed are list-generic now). Pill "Mute" (stage "mute": 1 hour /
  today / always) = `Notifications.mute` → a rule `{app: ^name$, toast/sound false, until}`;
  `sweep()` (60 s, only while needed) drops expired rules, history past
  `historyMaxAgeHours`, transients (30 min leak guard only). history=false → `transients`
  (not in the center), released once EVERY target island is done: the service picks the outputs
  once per arrival (`toastScreens()` → `entry.toastScreens`, `toastViews` = their count; 0 = no
  toast), only those islands take it, each hands it back once (`toasting` + `toastDone`: flow
  card gone via the derived `flowEntry`, ticker end, island destroyed). `toastViews > 0` = still
  on screen / queued (dedupe). Toast time = `toastMs`
  (urgency, rule, `appTimeout`; critical 0 = until dismissed, no queue shortening; the ticker
  then loops until hovered / fullscreen ends). Pills capped by `flowMaxActions` (Dismiss
  always; kept Copy > Reply > sender's > Mute).
  Toast displays: `notifications.screens` all | focused | only | except + `screenList`
  (connector names; set row `optionsFrom: "screens"` = connected + chosen-but-absent);
  decided by the service (focus not reported yet = the first output; nothing left connected =
  the focused one). Set pages are live (generated group "setChecks"). One monitor here: only
  the fallback paths were tested. `quiet` = DND switch || `dndWhileSharing` && sharing (Privacy screen
  nodes || own recording); `redact` (privacy off|sharing|always) = card/ticker show the app
  name only until the flow card is pulled open. `expireTimeout` is in MS (verified with
  notify-send -t). Dedupe = same app+summary+body replaces the older entry, silent within
  while the stored copy is on screen / queued (`toastViews > 0`) the NEW one is dismissed
  (never a critical one); later it replaces the copy. Rule regexes cached (`reCache`, reset on
  config change, own-key lookup: "constructor" as a pattern once broke every arrival). Mute
  writes its OWN rule (`mute: true`, reused on the next mute, deleted by sweep when its time is
  up) applied ON TOP of the first matching ordinary rule — stamping `until` on the user's rule
  deleted that rule with the mute; it withdraws that app's queued toasts on every output, the
  muted one included (`toastsWithdrawn`). Rule basics shared with settings:
  `services/NotificationRules.js`. Drops the user never saw (repeat, no toast + no history) are
  `expire()`d, not dismissed (apps read Dismissed as handled). A rule / app timeout is never
  shortened by the queue; sweep skips entries still on screen; a card in use gets a fresh
  `toastMs` when let go (`flowWaitsHold`); an until-dismissed ticker loops until hovered (also
  outside fullscreen) and makes newcomers queue. Sweep releases old entries even with
  `toastViews > 0` (an island that never reports back), and dedupe ignores a view count older
  than `transientMs`; a repeat that is not stored never releases a stored copy. A tapped
  transient is dismissed, not expired. Code words are whole tokens (JS `\b` ignores Cyrillic:
  "промокод" matched "код"); `entry.code` is a binding (follows `codeCopy`); in-place updates
  sync once (`Qt.callLater`). flowSwapGap dequeues the next card when the held one went away.
  `entry.code` = the 4–8 digit number nearest a code word → "Copy" pill (wl-copy).
  TransitionLayer.launch turnaround: stop() may land the flying element (finish → el null);
  lifting null threw and aborted openModule — queued flow cards never opened (pre-existing,
  fixed Oct 2026). Verified live via notify-send + debugState (notifs.timeoutMs/code, transients):
  drop/muted/transient rules, dedupe, code, critical 10 s / until dismissed + queue, timed
  rule removal, rule ids, queue advance. NOT tested:
  the pills by pointer, DND while sharing, redaction visuals, rule pages in the UI.
- Quick Settings (`modules/quicksettings/`, Oct 2026) = iOS Control Center: TABS (pages)
  of a 4-col grid of square cells (`Config.data.quicksettings`), island size/radius DERIVED
  in `QsMetrics.js` (radius = margins + unit/2; card radius = unit/2 → 1x1 circle, 1xN
  pill; viewport = TALLEST page, pages slide vertically inside one strip offset by the live
  `pagePos` — a swipe never resizes the island; + rail width when the rail shows). Layout
  is STATE, not config: `services/ControlCenter.qml` (`pages`, session `page`; shared by all
  islands, injected Shell → Island → services map) persists
  `Quickshell.statePath("quicksettings.json")` `{version 2, pages}` on edit end (v1
  `{items}` loads as one page; empty pages dropped on save). `QsGrid.js` = pure pin+push
  engine (moved card pinned, displaced cards try the vacated origin first → equal cards
  swap, else first free slot forward; empty rows squeezed on commit; drag previews always
  recompute from the committed layout). `QsCatalog.js` = ids + allowed footprints + glyph +
  default layout. Card content lays out by its SHAPE (`QsCard.form`: small/wide/tall/
  large/panorama — user: "свой layout под каждую ориентацию", iOS 27). Delegates: ONE
  stable Repeater over `QsCatalog.IDS` (y = page*stride + cell; other pages visible only
  while sliding — the edit footer sits where the next page waits; viewport clips only
  while moving). Tab rail (`QsTabRail`, right, vertically centred): icon = glyph of the
  page's biggest card, disc follows `pagePos`; system tray (`QsTray`, SNI, `quicksettings.tray`) =
  a block under the tab icons centred together with them (`QsTabRail.below/belowTop`, also with one
  page; sized via `ControlCenter.trayIcons` → `QsMetrics.railHeight`): left = activate + close QS,
  right / long press (holdMs) = the item's DBus menu as an expander panel (`panels/TrayMenuPanel`, submenus in place;
  QsMenuAnchor is useless here — it needs `//@ pragma UseQApplication`; debug IPC `quicksettingsExpand tray<i>`), middle = secondaryActivate; switch by vertical swipe/drag (cards forward
  theirs as swipe* in the static module's coords — the strip moves under the pointer), the
  wheel, a rail tap. CLOSE (user): tap on empty space, or swipe up STARTING in the bottom
  `closeZone`. The module owns ALL its presses (background MouseArea below the cards) —
  deliberate exception to "module content stays press-transparent"; GestureZones never
  sees QS presses. Edit mode (user, Oct 2026): ONLY a long press on EMPTY space, the rail's
  bottom-right edit button (`QsRailButton` "+", a check while editing, mirrors the session
  button; `quicksettings.editButton`) or IPC — a long press on a CARD never edits → drag body =
  move (over a rail icon =
  flip to that tab, over "+" = new tab), bottom-right arc = resize (nearest allowed size),
  "−" = hide, footer chips add back, «Готово»/tap on empty/module close saves.
  Expanded card (Oct 2026, user design): long press on a card with a panel
  (`QsCardFactory.panelFor`: wifi, bluetooth, vpn) → `QsExpander` = a thin QS wrapper over the
  GENERIC `components/DropExpand.qml` (user: reusable on any button, click or hold —
  `components/DropExpandArea.qml` trigger; `open(source, {panel, width, height, radius,
  sourceRadius, layer, color (value or live function), payload})`, panel item gets
  `expander`/`payload`; `close(fn)` runs fn after the drop LANDED — menu actions that remove
  the source; `lifted`/`landed` signals; motion = `Config.dropExpand`, per-instance
  overridable). The QS look (`openCard`): ONE shape in
  three spring phases chained by `expand.handoff` (next starts when the previous reaches it):
  card rect → drop (circle, short side × dropScale, on the card centre) → flight to the panel
  centre (VelocityDeform stretch) → grow to the panel. Panel size = free px
  (`expand.panels.<id>`, user: NOT grid cells), centre = card centre CLAMPED per axis into the
  GRID area minus margins (`boundsW` = viewport + margins; user: never over the rail column)
  (= the shortest move that fits). Card content = hideSource
  ShaderEffectSource of `QsCard.contentLayer` (card keeps its slot, `expandedOut` drops its
  surface), card-size layer scaled into the shape, blur-fades out; panel laid out at its final
  size, scaled with the shape, blur-fades in on grow (FadeBlur). Fill = card look (accent × onP)
  → `Theme.qsPanelBg` (a touch darker than frostButton). The rest of QS does NOT change
  (no dim): the module's `backdrop` layer is cut out under the shape by an inverted
  binary MultiEffect mask (`cutout`, inset `cutInset`, follows the flight deform), and the
  shape draws the grid BLURRED under its fill instead (user, Oct 2026: blur what is behind,
  not a hole — `DropExpand.backdrop` = the `viewport` item at `backdropPos`, ShaderEffectSource
  + MultiEffect blur `expand.blurMax`, masked to the shape inset `cutInset`; `expand.blurBehind:
  false` = the old bare cut). The sharp grid must stay cut out, or it shows through the blur's
  translucent edges/gaps. Frost: the shape is NOT a hole —
  the module's `knockoutClear` ({x,y,w,h,r,m,inset} via ModuleHost) makes Island cut its tint
  out under the shape with the same inverted mask (`frostClearMask`); card holes stay as they
  are (dropping / cutting the holes of partly covered cards recoloured them — the "artifacts"). Fast springs (user): drop 14, fly / grow / fades 12, handoff 0.5. Tap outside = the
  same phases backwards (card content returns while the drop flies home). Wi‑Fi panel
  (`panels/WifiPanel` + `WifiRow` + `WifiField`/`PanelPill`/`PanelButton`; multi-step nmcli in
  `scripts/network/wifi.sh`): header disc toggles Wi‑Fi, rescan button (`PanelHeader.trailing`);
  list from `Network.networks` (`setScanning` while the panel exists: list every `scanMs`,
  `nmcli device wifi rescan` every `rescanMs` — NM rescans rarely once connected), sections
  "Known" / "Other" (ListView section), order current → saved → signal bars → name. `known` =
  a saved profile whose `802-11-wireless.ssid` matches (`Network.saved`, ssid → uuids/keyMgmt;
  NOT the profile name). Tap: current → details; saved/open → join (`connection up uuid`); new
  secured → password field (+ user name for 802.1X: PEAP/MSCHAPv2 profile). Right click / long
  press / "…" → chips Details · Share (QR via qrencode + the saved psk) · Disconnect · Forget
  (asks once more). A failed join keeps nmcli's "Error:" line (NOT the last one — that is a
  "Hint: journalctl…") → `failReason`; "password" reopens the row's field even for a saved
  network, and a password given for a saved one is stored into it (`wifi.sh psk`). Hidden
  network ("Other network…"): NM with the **iwd** backend refuses `device wifi
  connect … hidden yes` ("'ssid' scan option not supported") → `wifi.sh hidden` = a
  `wifi.hidden yes` profile + up, deleted again if that fails (same for a new 802.1X one).
  Captive portal: `nmcli networking connectivity` == portal → status + a sign-in row
  (`network.portalUrl`). "Network settings…" = `launcher.apps.terminal` + nmtui. Keyboard:
  the panel ALWAYS wants it (Island Exclusive while it is open): ↑/↓, Enter = tap, → actions,
  ← fold, Esc fold / close. Motion (all springs): ListView add (cascade) / remove / move /
  displaced transitions; `Network.savedReady` holds the list until the saved profiles are in
  (else every row re-sorted across the sections right after opening); row tail (lock, check)
  pressed right, hover / selection / open row slides it left and "…" grows in; check pops,
  state line unfolds, chips cascade (`PanelPill` width + SpringColor fill), sections rise in
  (`Appear` via a Translate — the Column owns y), the row clips while its height springs
  (the unfolded part is laid out full size), a failed-password reopen shakes the field,
  header status blur-fades (`PanelHeader`), the refresh glyph springs on to a full turn. Debug IPC `quicksettingsPanel <cmd> <arg>` (WifiPanel.debug: state
  JSON, tap/menu/action/fill/other/forget/rescan/portal/settings); live test
  `temp/wifi-panel-test.sh [out]` (git-ignored; DROPS the connection several times, restores
  the psk and reconnects on exit) — passed Oct 2026 incl. wrong password → re-enter. NOT
  tested: a real hidden / 802.1X / captive-portal network (portal look only via the fake). Bluetooth panel
  (`panels/BluetoothPanel` + `BluetoothRow`; shared `PanelHeader` + `PanelSync.js` (ListModel
  in-place sync) with Wi‑Fi, sizes `quicksettings.listPanel`): adapter discovery while the panel
  exists, paired (connected first) + NAMED nearby devices, rows look the device up by address
  (live state), tap = disconnect / connect / pair → trusted + connect. `services/Bluetooth`
  used `adapter.powered`, which does NOT exist in Quickshell (`enabled` does): the card read Off
  forever, toggle dead — fixed. Panels get services through the factory's Component bindings.
  State that survives a reboot (statePath files): Wi‑Fi / Bluetooth switch (`wifi.json` /
  `bluetooth.json`, saved only on taps in the card/panel), Airplane Mode (`on` in `airplane.json`;
  systemd-rfkill is masked here), Caffeine, brightness (systemd-backlight keeps nothing for
  gmux_backlight), default-sink volume+mute (`volume.json`, per node name, re-applied to the
  sinks that are default in the first 20 s, each once: a dummy / HDMI sink may come first).
  Radios, volume and brightness are re-applied once per login (markers
  `$XDG_RUNTIME_DIR/flicker-{radios,volume,brightness}-restored`; a hot reload would undo nmcli
  changes / restore a level saved before the debounce); brightness only to the device it was
  saved for. Radios are orchestrated by Airplane: Airplane on at start = re-blocked, the switches
  are skipped; persist.airplane off = the saved `on` is forgotten. Only rfkill op 2 (state
  change) counts as the mode switching — devices removed at shutdown / re-listed after a watcher
  restart can leave all remaining ones blocked. Any exit (Fn key / rfkill elsewhere too)
  restores each radio once it is unblocked (Wi‑Fi through Network.applyRadio: snapshot, else the
  saved switch; partial exit = only those), the snapshot goes once nothing the mode blocked is
  soft-blocked. `bluetooth.autoOffMin` (10, 0 = never): adapter off after that long with no
  device connected / connecting / pairing and no discovery; not saved as the switch state. Re-applying each one on start is gated by
  `persist.{wifi,bluetooth,airplane,caffeine,volume,brightness}` (all true; the state is saved
  regardless) — settings: Quick Settings → Keep after reboot, Sound, Volume & Brightness.
  Shared helpers: `services/StateFile` (statePath JSON, read() = {} on missing/bad, write(obj)
  adds `version`) and `services/LoginOnce` (claim() = first time this login).
  Debug IPC `quicksettingsExpand <id>` ("" folds back). Verified via that IPC + grim frames
  (both ways, both panels; BT discovery found nearby devices). NOT tested: the real long press,
  BT connect / pair taps.
  Audio panel (Oct 2026, user: everyday controls here, the full set in settings → Sound)
  = `panels/AudioPanel` + `AudioDeviceRow` / `AudioStreamRow` / `PanelSlider` over the SHARED
  `services/AudioDevices` (+ pure `services/AudioGraph.js`; one instance in Shell, injected as
  `services.audioDevices` and into SettingsScope). Opened by the MEDIA CARD's output button (no
  "audio" card): `QsCardFactory.expandRequested(source, id)` → `QsExpander.openPanel` (the
  button is the drop's source; `expandedOut` only on cards). Debug: `quicksettingsExpand audio`,
  `quicksettingsPanel scroll <px>` / any other cmd = rows JSON (two args always). ONE row per
  physical device: endpoint = follow `filter-chain-*` / `echo-cancel-*` link groups
  (PwLinkGroup; the echo canceller's `stream.monitor` reference stream is skipped) to the first
  non-filter node; key = STABLE endpoint identity (`api.alsa.card.name/alsa.name`, `bt/<ADDR>`,
  else node.name — device.id changes per PipeWire start) — the T2 DSP filter-chain sink ends in
  the Internal `hw_Audio_0` and the raw HiFi Speaker sink (UCM split loopback) is pcm Speaker of
  the same card → one "Built-in Speakers"; DSP mics + raw mic + voice processing → one row.
  `resolved: false` = endpoint not found yet (links not read at start-up): never learned. Row
  node = default if in the group, else the shallowest filter. Card ports no node covers (pactl
  JSON, ALSA only): plugged → switch port / profile, unplugged Headphones / Headset → dimmed. A
  profile switch makes the new node default when it appears (`pending`, 5 s). BT: Music / Calls
  pills; a headset in A2DP shows as an input row that switches to calls (`sub: "callMode"`).
  Mixer: `Stream/Output/Audio` without a link group, `pactl move-sink-input <object.serial>`
  (pipewire-pulse indexes sink inputs by SERIAL). Mic level = `PwNodePeakMonitor` (node
  "quickshell"). `Audio.isShellCapture` drops "quickshell" and every `flicker_*` node.
  pactl lists are re-read on card events / sink-source add-remove / server (NOT every volume
  change). Known devices = `Quickshell.statePath("audio-devices.json")` {outputs, inputs} in the
  user's PRIORITY order (rows sort by it; settings list + fallback). `learn()` is deferred
  (`known` feeds the rows' order — binding loop).
  `services/AudioPolicy` (Config.audio): autoSwitch always / ask (event, tap = switch) / never
  (undo WirePlumber's switch to the newcomer), followPriority (current device gone → first in
  the known order), btReturnToMusic (a call profile goes back to A2DP once the app that recorded
  from the BT mic stopped `btReturnDelayMs` ago — a manual "Calls" without recording stays),
  balance {key: -1..1} re-applied on `volumesChanged` (Quickshell's `volume` setter and wpctl set
  every channel alike; volumes are cubic: -0.3 → right ×0.343 linear), headphone cap
  (`Audio.personalOutput` → `maxVolumeHeadphones`), voice processing (`scripts/audio/audio.sh
  voice` = a standalone `pipewire -c` client with module-echo-cancel + aec/libspa-aec-webrtc,
  `monitor.mode` reference, passive streams; its source `flicker_voice` is made default, choosing
  another mic re-targets it, off → back to the real mic first; 5 quick exits = give up), listen
  to yourself (pw-loopback, only on headphone-like outputs), channel test (`audio.sh test`: the
  mono freedesktop voice panned to one side, cached in $XDG_RUNTIME_DIR/flicker), WirePlumber
  settings (`wpctl settings [--save]`: mono = `node.features.audio.mono`, live; BT autoswitch,
  profile preference, pause / mute on removal, restore-target), remembered app outputs
  (WirePlumber's stream-properties "target"; `scripts/audio/forget-routes.py` STOPS wireplumber,
  edits, starts it — it keeps the file in memory). Settings → Sound = `SettingsSchema` section
  "sound" + `SettingsAudio.js` (generated device lists / device page / app outputs; stores
  `audioDev`, `wp`, `audioPolicy`; dependsOn `audioPolicy:` / `wp:`). `SettingsWindow.groupsOf`
  returns the PREVIOUS array when the generated result is unchanged (a config write rebuilt every
  row — a balance drag lost its slider). "System sounds" = `audio.eventVolume` (Notifications'
  pw-play `--volume`; the timer alarm is NOT scaled). Verified: IPC + grim (fake pw-play / pw-cat
  streams), device page via vmouse, balance on the DSP sink's channelVolumes, voice processing
  on → default `flicker_voice` fed by the DSP mic → off restores. NOT tested: headphones / BT /
  USB / HDMI live, auto-switch / ask / priority fallback, the channel test sound, listen to
  yourself, forget-routes, the real button click, routing with 2+ outputs.
  Slider cards (`cards/SliderCard.qml`, volume/brightness) = the OSD look: the card IS the
  capsule (`ownSurface` → QsCard drops its bg so the gap shows the island), fill | gap |
  track with `Config.osd.gap/innerRadius/fill*` springs, glyph + title drawn twice (light
  over the track, dark clipped to the fill), no percent; volume = VolumeIcon (arcs by real
  level, slash on mute, pulse at 0 / wave at 100%, orange fill past 100%).
  Media card (`cards/MediaCard.qml` + `MediaLayout.js`): one element set MORPHING across
  1x1/2x1/4x1/2x2/4x2/4x4/4x6 — every rect springs to its per-footprint target (computed
  from the TARGET footprint, not the animated card size), missing elements leave/arrive
  via `components/FadeBlur.qml` (blur rises as opacity falls); 4x2 = the player module
  layout (player px × `playerScale`); buttons are the player's own
  (`modules/player/{TransportBtn,SkipBtn,PressDisc}.qml`, extracted from PlayerModule); the
  lyrics spot is the audio-output button (`openOutput` → `panels/AudioPanel` through the QS
  expander, glyph = current output); 4x4/4x6 add a
  system-volume row (speaker · bar · speaker) under the transport (`audio.quiet()` → no OSD).
  4x4/4x6 (edge inset = 2× the 4x2 margin): transport row = like (placeholder) · prev · play ·
  next · output (bare grey glyph, disc springs away); the output's old spot holds
  `components/AudioBars.qml` (cava, pulse auto = output monitor, mono, `Config.visualizer`;
  runs only while shown + playing + visible). Mic filter: match cava by `node.name` —
  `application.name` arrives AFTER the node appears (app-only match lit the mic indicator).
  Stub cards (Oct 2026, hidden by default, no backend): magnifier, voiceMemos, notes,
  translate (status = language pair), lowPower, airplane, cellular, dictation, stopwatch, timer,
  calculator, mirroring, focus — one `stubComp` ButtonCard driven by
  `QsCardFactory.stubs` (toggles flip a session-only local `on`); give a card a real Component
  in `componentFor` when it gets a service. Hotspot = «Режим модема», record = screen recording.
  Screenshot/record/scanCode (capture mode `scan`) cards go through `Island.runQuickAction` (close, wait
  `actionDelayMs`, then capture — the grab must not show the open grid). The state file
  is read once at load (no watch): to test a hand-written layout, change it and force a
  reload with a real content change of a QML file (`touch` is ignored). Debug IPC:
  `quicksettingsPage <i>`, `quicksettingsResize <id> <w> <h>` (saves! restoring the file
  afterwards is NOT enough — the service keeps the resized layout in memory and saves it
  again on the next edit; force a reload after restoring) — verified with
  them: 4x2↔2x2 morph frames, 4x4/4x6 layouts, page slide + rail.
  NOT live-tested (no mouse tool): drag-move (incl. across tabs), resize arc, remove/add,
  taps, slider drags, swipe paging/close zone, wheel.
- VPN (Oct 2026, user port of their dots-hyprland "ii" Vpn service): QS card `vpn` (catalog
  BUTTON_WIDE, starts hidden) + expanded `panels/VpnPanel` (PanelHeader with `shape: "cookie9"`
  = MorphDot disc: `spinning` while up, `busy` leaps through random MorphShape kinds — NOT
  M3Shapes, see Lock; node list, ping / speedtest-cli pills, autostart switch, restart, logs
  (terminal `journalctl -f -u sing-box -u xray`), subscription URL form), IPC `island vpn`,
  `services/Vpn.qml` (Shell → Island `vpn` → services map + IslandIpc), backend
  `scripts/vpn/vpn.sh`. Engine = system unit `sing-box.service` (Arch: User=sing-box, runs
  `-C /etc/sing-box` = merges EVERY *.json there — never write temp/backup *.json into it).
  Nodes = the first `selector` outbound's list, active = its `default` (switch = rewrite +
  try-restart; sing-box only restores a cached choice made via Clash API, so the default
  wins). Status = `vpn.sh state` JSON poll: unit + an HTTP probe through it (`curl -4`),
  `connecting` until the probe answers, `offline` after `stallMs` without it (+ event).
  Subscriptions: `sub_parser.py` (user's own, Throne-style) → sing-box JSON (DNS: proxy
  servers' domains direct, everything else `dns-remote` through the proxy; `store_dns`, not
  the deprecated `store_rdrc`) + an extras JSON of link params sing-box has no field for.
  Arch's sing-box is built WITHOUT `with_grpc`: its lite gRPC sends `:authority` = the SNI
  (for REALITY the camouflage domain) and Xray servers drop the stream ("connection upload
  handshake: io: read/write on closed pipe"). So `xray_split.py` moves gRPC / XHTTP nodes
  (vless/vmess/trojan) to Xray (`xray-bin`, `xray.service` User=xray): one Xray outbound per
  node behind its own 127.0.0.1 shadowsocks-2022 inbound (`2022-blake3-aes-128-gcm`, random
  free port + fresh random key per node per import — NOT SOCKS: its password covers TCP only,
  UDP datagrams are unauthenticated), the sing-box outbound of the same tag becomes a
  shadowsocks client to it (selector unchanged); sing-box has NO local inbound besides TUN
  (an open mixed / DNS port lets any local program ride the tunnel and see the exit IP);
  Xray's uid is excluded from the TUN (`tun.exclude_uid`) + routed direct (`user_id` rule) —
  no loop. Xray 26.3.27's own TUN inbound only raises the interface (routes / loop avoidance
  are the OS's job; `autoSystemRoutingTable` exists only on main), hence sing-box stays the
  engine. Xray picks the config format by EXTENSION: `xray run -test -format json` on mktemp
  files. Xray removed `allowInsecure` (2026-06): such nodes verify (view type "⚠ cert
  checked"). Secrets: both configs root:<unit user> 0640, `.bak` 0600; the panel reads
  `/etc/flicker-vpn/view.json` (0644, written by the root halves: profile, profiles
  [{tag, type, base, xray, insecure}], xray). Privileges: root halves (`_select`, `_apply`,
  `_routing`, `_reroute`, `_killswitch`) via pkexec (the shell's polkit agent asks); start/stop
  via systemctl + polkit. `vpn.sh setup` copies the scripts to root-owned
  `/usr/local/lib/flicker-vpn` and installs a rule: the units, plus pkexec of THAT copy for
  `_select` and `_reroute` (routing-only apply, overlay = root's applied copy) without a
  password. Never the user-writable script, never overlay changes / subscriptions (sing-box
  has CAP_DAC_READ_SEARCH: an overlay could serve any file). Root halves run from the copy
  while it matches the scripts (else from the repo, always asking: re-run `setup` after
  editing them); password-free input is untrusted — routing as a JSON string, rule-sets via
  `routing.py install-rules` (O_NOFOLLOW, owned by PKEXEC_UID). An update keeps the
  chosen node if the new subscription still has it.
  Kill switch (`vpn.sh killswitch on|off`, panel switch): `flicker-vpn-killswitch.service`
  (oneshot, loads `/etc/flicker-vpn/killswitch.nft` = table `inet flicker_killswitch`, output
  hook: accept lo, the TUN (fixed `interface_name: flicker-tun` — the switch renames an older
  config's TUN), sing-box / xray uids, `ct status dnat` (auto_redirect's TCP: the filter hook
  still sees the pre-NAT oif), LAN except DNS 53/853; reject the rest). Pulled in by a
  `sing-box.service.d/flicker-killswitch.conf` `Wants=` drop-in (presence = "on"), so every
  start incl. boot raises it; a crash / failure leaves it up (state `blocking`, status
  `blocked`, panel "Release block" = `vpn.sh stop`); only `vpn.sh stop` lowers it — a manual
  `systemctl stop sing-box` does NOT. Verified in an `unshare -rn` netns with dummy links.
  Split routing + config overlay (`routing.py`): config.json = compose(base, routing,
  overlay). base = `/etc/flicker-vpn/base.json` (sub_parser + xray_split, root 0600; `_select`
  edits it too, or a recompose would switch back). routing = Config `vpn.routing` ({ final:
  proxy|direct, rules: [{ action: proxy|direct|block, match: [...], enabled }] }, first match
  wins; matchers domain:/full:/keyword:/regexp:/ip:/process:/path:/protocol:/geosite:/geoip:
  `name[@source]`, sources runetfreedom → metacubex → sagernet, .srs downloaded by the USER
  half with `curl -4` to ~/.cache/flicker/vpn/rules (fresh for a day; a stale copy beats none),
  root copies the needed ones to /etc/flicker-vpn/rules as `local` binary rule-sets). Each rule
  = an inline rule-set `flicker-r<i>` (+ geo sets) → one route rule; protocol: is a route field
  (not allowed in rule-sets), `ip_is_private` is NOT allowed in rule-sets either (LAN = a fixed
  route rule, always direct — before this LAN went through the proxy). DNS mirrors it
  (`flicker-d<i>` = the domain kinds + geosite: direct → dns-direct, proxy → dns-remote, block
  → reject; the catch-all follows `final`). overlay = ~/.config/flicker/vpn/custom.json
  (`vpn.sh edit`, panel "Edit config"): deep merge, null deletes, tagged arrays merge by tag,
  route/dns rules go in front (after sniff / hijack-dns / Xray's uid rule). `sing-box check`
  validates NO tag references (dangling outbound / DNS server / rule-set pass it and fail at
  start): routing.py `check_refs` does. `vpn.sh apply [json] [refresh]` → pkexec `_routing`:
  compose, check, install, restart; not up 3 s later → `.bak` restored, error, copies
  (/etc/flicker-vpn/{routing,custom}.json) not updated so it stays pending. view.json carries
  `routing` + `customHash`; Vpn.qml `pending` = canon(Config routing) ≠ applied, or the
  overlay's hash changed → panel "Apply routing changes". Tested end to end with /etc mapped to
  a scratch dir, pkexec = `unshare -r`, systemctl stubbed.
- Launcher (`modules/launcher/`, Oct 2026) = pShell launcher port, only the apps + clipboard
  plugins. `LauncherModule` (host: plate-less search row, hairline divider (`launcher.dividerInset/Width`, `Theme.launcherDivider`, centred in `gap`, short of the edges) / list / plate-less side panel behind a vertical hairline (the same `panelGap` list edge → line → panel content, counted in `LauncherMetrics.islandSize`; the list narrows by `panelListShrink` (0.3) while the panel is open, rendered width on the island's own `Spring {}` so both move in step; `panelDividerInset` short of both the horizontal divider and the island bottom, fades with the panel)) + `LauncherManager`
  (pShell ModuleManager: default → `!` picker → active plugin pill; Backspace on empty steps
  back, active needs a double press within `escapeMs`, the tag turns red in between).
  Plugin = folder `plugins/<id>/` with `XxxManifest.qml` (`api/LauncherManifest`: `pluginId`
  — `id` is reserved in QML — title/icon/trigger, lazy `content`) + a `api/LauncherPlugin`
  (listModel entries in UniversalDelegate format, `hasRightPanel`/`rightPanelComponent`,
  `inputExtensionComponent`, handleInput/onActivated/handleExecute, requestClose). Listed
  EXPLICITLY in `PluginRegistry.qml` (no FolderListModel scan: the scanner misses imports of
  dynamically created files); `config.launcher.order/disabled` by id, order[0] = default.
  `api/` is its own dir so plugins (`import "../../api"`) and the registry never import each
  other's dirs in a cycle. Search = `fuzzysort.js` (pShell copy, fzf.js dropped). Island
  size: module `preferredWidth/Height` (`LauncherMetrics.js`, radius = `launcher.radius`, 0 = padding +
  inputHeight/2) → `ModuleHost` → `Island.moduleSize`; full-list estimate before the
  handover; `surfaceReserve` holds the max height while open (list resizes per keystroke).
  The list is NOT a drag-Flickable (press-transparency): own `selected` index (ListView's
  currentIndex auto-scrolls), wheel steps it, contentY springs to keep it in view.
  Result motion (user pick over caelestia/DMS/end-4 styles, Oct 2026): rows are cached
  per item (apps per DesktopEntry, clipboard per cliphist id, picker per manifest) and
  LauncherList feeds the view its OWN ScriptModel over a WINDOW of `manager.entries`
  (visible rows + `windowExtra`, growing past the selection; all window rows kept
  created via cacheBuffer). Without the window the first letter / erasing a word arrived
  as mostly row MOVES (54 moves vs 2 removes measured) — a row moved in from off-screen
  was created fresh (no animation), one moved away destroyed at once (user: "не везде
  срабатывает"). Rows
  that come fade in out of a blur, leaving rows dissolve (fast critically damped
  `remove*`), the rest FLIP-slide (row offsets itself by old−new y, springs to 0), one
  selection plate springs between target slots (VelocityDeform stretch in flight, user — velocity from the slot in LIST
  coords via `useSource/sourceY`: a held key scrolls the list and the plate stands still on screen;
  attenuated by the row height `sizeW/sizeH`, the list width cut it to ~9 %); `listKey` change (plugin / "!" picker) =
  whole-list FadeBlur out → swap → in. scrolling is on the ROWS (user): `scrollTo` sets contentY at once and
  emits `scrolled(d)`; every row (`LauncherItem.kickScroll`) and the plate offset themselves back by
  d and spring to 0, rows farther from the selection softer (`launcher.scrollStagger`). Only OUR
  scrolls kick (a Behavior on contentY was stopped by ListView's own writes; ListView shifts
  contentY itself on inserts above the top row — animating that made the list jump); the row WINDOW is grow-only per list (`reach` =
  furthest selection; shrinking it while scrolling back up made ListView clamp contentY itself
  = an unanimated jump, verified in a scratch harness); scroll springs `launcher.scrollStiffness/
  scrollDamping` (stiffer than motion*); while scrolling the window keeps maxShown extra rows AHEAD
  (`baseCount`+, added with `quietAdd` = no new-result fade) and the view has display margins of a
  list height (rows there are created synchronously, cacheBuffer incubates async) — lagging rows
  never leave an empty band at the edges (harness gap metric: ≤2 px at 18 ms steps): ListView shifts contentY itself on inserts
  above the top row, animating that made the list jump up and back. Tunables `launcher.motion*/appear*/remove*/
  rowBlurMax/hoverHoldMs/windowExtra`. Verified frame by frame in a scratch overlay PanelWindow
  (`grabToImage` at 80/200/450 ms + row dumps) — a FloatingWindow off-screen on driftwm
  gets no frame callbacks, its animations freeze and the frames lie. A re-open
  over the open launcher only swaps the payload (`onPayloadChanged` → `applyPayload`).
  Apps launch through `launcher.apps.launchPrefix` (app2unit). Clipboard history is fed
  by `services/ClipboardWatch.qml` (Shell → Island → `launcherHost.clipboardWatch`): `watch: "auto"`
  starts own `wl-paste --type text|image --watch cliphist store` (argv[0] `flicker-clipwatch`,
  restarted on exit) unless an external one runs (niri spawns it, driftwm does NOT); each store bumps
  `revision` → an open clipboard plugin re-lists. Verified live on driftwm: text + PNG stored.
  Verified via IPC on the live instance + a headless harness (state machine, picker,
  fuzzy, double Backspace). NOT live-tested (no keyboard/mouse tool): typing, Enter/Alt+Enter,
  launching, copy/auto-paste, wheel, hover, the details toggle.
- Wallpapers launcher plugin (`plugins/wallpapers/`, Oct 2026, backend **wallr** 0.6.4 — user
  decision after a source audit; spec/decisions in `temp/wallpapers-plugin-spec.md`). Launcher API
  grew for it: `LauncherPlugin.bodyComponent/bodyWidth/bodyHeight` (a body REPLACES list + panel,
  `LauncherMetrics.islandSize({body})`, `estimate()` pre-handover, `maxHeight` counts
  `wallpapers.cardHeight`), `handleKey(event)` (first chance at keys in the search field),
  `host` ({screen, originX/Y} = bar centre normalized, y from top — Island services `launcherHost`).
  Plugin owns the state (`entries`, `selected`, animated `pos` on a Spring whose params come from
  `wallpapers.speeds[speedLevel]`: single step / quick steps within `speedWindowMs` / auto-repeat
  + jumps; jumps > `flyMax` snap); `WallCarousel` only draws a WINDOW of cards (ScriptModel slice
  around round(pos), `CarouselMath.reach`) — folders hold thousands of files. `CarouselMath.js`:
  width/height/x per offset d (body = `visibleCards` cards, tiers `cardWidths[k]`/`cardHeights[k]` by |d|, gap stays exactly
  `cardSpacing`), parallax = art wider than the card shifted −d·parallax (clamped to the overscan).
  GIF/video play in the centre card `playDelayMs` after it rests (AnimatedImage / MediaPlayer+
  VideoOutput, muted, looped). Thumbs on demand (`thumbAhead` around the selection) via
  `scripts/wallpapers/thumbs.sh` (ffmpeg, `thumbJobs` parallel) → `~/.cache/flicker/wallpapers/
  <md5(path|mtime|size)>.jpg`; scan `scripts/wallpapers/scan.sh` (dot DIRS skipped; dot FILES = hidden wallpapers, listed with
  `hidden: true`; thumb key ignores the dot), rescan
  only when the dir-mtime signature changes (poll `rescanMs` while active). Live preview (fade,
  `--no-theme`) after `previewDelayMs`; Esc/close/other plugin restores the original read from
  `~/.cache/wallr/last_wallpaper/<output>` (execDetached from onDestruction). Enter = this output,
  Alt+Enter = all; effect `island` = `grow -o <bar centre>`. Prefixes `v `/`g `/`i ` filter type.
  Scrolling: mouse wheel = vertical (notch = 1 card), touchpad = horizontal only
  (`touchpadStep` angle units per card). Traps hit: Qt on Wayland reports the touchpad as a
  Mouse device (tell it apart by scroll phase / pixelDelta); `WheelHandler` sees only events
  along its `orientation` (default Vertical → pure horizontal swipes never arrived, only
  diagonals) — a `MouseArea { acceptedButtons: Qt.NoButton; onWheel }` gets both axes;
  touchpad = phase/pixelDelta seen within `touchpadHoldMs` (slow finger motion rounds
  pixelDelta to 0) → x only, else wheel → y only; touchpads also interleave zero-delta events (must not reset an
  accumulator).
  Trap hit: `service: service` in the carousel Component = self-reference (renamed `wallService`).
  Edits to `plugins/wallpapers/*` did NOT hot-reload the live instance (only files the scanner
  saw are watched) — force it with a real edit of e.g. `PluginRegistry.qml`.
  Shell-wide `services/Wallpaper.qml` (Shell → Island → `launcherHost.wallpaper`, IslandIpc):
  favourites + history (paths, newest first) in `Quickshell.statePath("wallpapers.json")`,
  `apply()` (every real set → history; `noteCurrent` seeds it with wallr's current on open),
  `random(output)` (`island wallpaperRandom`, `randomFrom` all|favourites, never the current),
  `setHidden()` ("name" <-> ".name" via `scripts/wallpapers/hide.sh`, queued, result in
  `hideDone` → the carousel rescans if it did not land as assumed; an identical twin under the
  new name → source to `gio trash`, a different one → "<stem>-<n>"; byte-identical name/.name
  twins happen, and `mv -n` silently did nothing on them — cards "came back"),
  random skips hidden; hide/fav chords ignore auto-repeat, video pause `wallr ipc pause/resume -m <out>` per screen on
  fullscreen (`pauseOnFullscreen`) / battery (`pauseOnBattery`) / SESSION LOCK (wallr 0.6.4 presents
  via Vulkan FIFO, ignores frame callbacks; under a lock the present blocks and its play_video loop
  stops for good after 5 s without an uploaded frame — "Video playback stalled, stopping"). A PAUSE
  > 5 s kills it too: last_frame_at is not refreshed while paused, the first resumed iteration
  without a ready frame stops playback (measured via wallr CPU: 4 s pause → plays, 7 s → dead, also
  after every fullscreen window > 5 s). `resume`/`reload` can't revive it; `set` of the same path
  with the same effect is a no-op → WallrClock's resume after > `wallrStallMs` runs
  a revive (wallrctl.sh resume … 1): two instant sets (`-e wipe -d 0ms`, then `-e fade`,
  --no-theme), then a seek back to the position frozen at the pause. Source: github programmersd21/wallr v0.6.4, daemon/mod.rs play_video / set_wallpaper.
  Check playback = wallr's CPU ticks (/proc/<pid>/stat), not screenshots (windows move). Plugin split: WallKeys.js
  (Ctrl+A/E ends, Ctrl+R random card, Ctrl+Shift+A/D fav, Ctrl+H hidden view normal→include→only (pill on top, eye-off badge on
  hidden cards), Ctrl+Shift+H hide/unhide, Ctrl+[/] history —
  Ctrl combos also match xkb keycodes so they work on the ru layout), WallFilter.js (prefixes
  v/g/i/f/h), WallActions.js, WallPreview.qml. Removal motion (WallFlip.js, any same-query
  rebuild: hide, delete, unfavourite under "f "): survivors FLIP (`WallCard.shift` = old−new d,
  springs to 0 on `close*`; set via `flipNonce`, newcomers read `flip` in onCompleted — so it is
  cleared right after the rebuild (Qt.callLater; a stale flip made cards entering the window
  later fly in from their old slot) and
  is assigned BEFORE `entries`), gone cards dissolve as ghosts (`leavingModel`, BlurSurface +
  fade + `leaveShrink` on `leave*`), a removed centre is replaced from `lastDir`'s side;
  hide/unhide in the "include" view keeps the card (`renames` → same slot). Every survivor is
  `instant` (no rise-in): the Repeater RECREATES moved delegates — they blanked for ~1 s.
  fuzzysort ranks through a heap: EQUAL scores come out in an input-dependent order (node:
  abs-1, abs-3, abs-2), so with a query a removal reshuffled the ties far from the gap —
  WallFilter.rank buckets the hits by `_score` (no `score` field here) in list order — LINEAR:
  a comparator sort with Map lookups took 1.3 s for 3300 hits in QV4 (first letter 1.6 s →
  0.33 s, mostly fuzzysort itself; a ONE-letter query skips fuzzysort: starts-with, then
  contains, list order — `WallFilter.oneLetter`). Same-query rebuilds (hide/delete/rescan) don't re-search:
  `WallFilter.refine` filters the current order (`prevFiles` = paths the last rebuild saw; a
  file not among them → full search). Slideshow = `services/WallpaperSlideshow.qml` (child of
  Wallpaper; `active` + `spec` {filter, query, visibility} persisted in wallpapers.json): step
  every `slideshowIntervalSec` on all outputs, pool = a carousel view re-resolved by a fresh scan
  (WallEntry + WallFilter), order random (avoids `slideshowNoRepeat` recent) | sequential, still
  images only on battery; carousel Ctrl+S = start over the current view / stop, `hold` (Binding
  to the plugin's isActive) skips steps while the carousel is open; IPC `wallpaperSlideshow`
  (toggle, all files) / `wallpaperNext`. Thumbnail warm-up = `services/WallpaperWarmup.qml`:
  `warmupDelaySec` after start + every `warmupRescanMin`, missing thumbs in batches through
  thumbs.sh (`warmupJobs`, nice), off on battery. `WallEntry.js` = the ONE entry/key builder
  (carousel, slideshow, warm-up must hash identically). Status pills (WallPill) on the carousel
  top: hidden view, slideshow, duplicate search. Ctrl+Delete = `gio trash` (service queue,
  `trashDone`; the card dissolves like a hide). "d " view = visual duplicates:
  `services/WallpaperDupes.qml` runs `scripts/wallpapers/dupes.py` (system python3 + Pillow) on
  the carousel THUMBNAILS: dHash candidates (8×8-bit bands) verified on a 16×16 RGB miniature
  (per-channel / mean diff + contrast-normalised luminance ≤ `dupesMaxZ`; near-flat images must
  match exactly) and grouped around a representative (no A~B~C chaining). Calibrated on a
  real folder: dHash + union-find alone gave huge groups of dark/minimal wallpapers; real
  duplicates (incl. 7680×4320 vs 1920×1080) sit at z ≤ 0.13, distinct dark ones ≥ 0.26. Fingerprints cached in `<thumbCache>/dhash.json` (~2 s warm, ~15 s cold);
  refreshed when the warm-up goes idle and on opening the view if older than `dupesMaxAgeMin`.
  Caption line `detail` = "n of m · W×H · size"; a group left with one visible member drops out.
  Process stdin one-shot: `stdinEnabled: true`, write() in onStarted, then `stdinEnabled = false`
  = EOF. Quick Settings card `slideshow` (QsCatalog, hidden by default — add it from the edit
  footer; `services.wallpaper` in the module services map). Every wallr set (apply, random,
  slideshow, live preview + restore) goes through `Wallpaper.setOn` → `scripts/wallpapers/
  setwall.sh`, one call per output (pixel size): adaptive fill-blur (walltool idea) — a still
  image whose aspect ratio is off by more than `fillBlurThreshold` is composed whole over a
  blurred (blur at 1/8 size: ~1 s for 3500×5000), darkened copy at the output's size, cached in
  `<thumbCache>/fill/<md5>.jpg` + `.src` (original path); `scripts/wallpapers/current.sh` maps
  wallr's last_wallpaper back through `.src` so the carousel still centres on the original.
  wallr restores only outputs it has a last_wallpaper for (a new monitor stays empty) →
  `Wallpaper.fillNewOutputs` (start + `fillNewOutputsDelayMs` after `screensChanged`;
  `fillNewOutputs`) runs `scripts/wallpapers/unset.sh` and sets such outputs to another
  output's wallpaper (else history[0]), no history push. Verified live on niri (DP-5, Oct 2026).
  Accent from the wallpaper (`accentFromWallpaper`, default on): `Wallpaper.updateAccent` runs
  `matugen image <path> --json hex --dry-run --prefer saturation -m dark` (matugen 4 refuses
  without --prefer when not on a terminal) and sets `Theme.wallAccent` = palettes.primary
  [`accentTone`]; Theme `qsBlue`/`cardBlue` follow it (transparent = stock blues). Runs on every
  apply + at start / config change (current.sh). GIF/video keep the previous accent. The island
  body stays black. Semantic search (Oct 2026, model chosen after a comparison: mexma-siglip2,
  MIT — MEXMA multilingual text + SigLIP 2 So400m/512 image, XM3600 text→image R@1 62.5 vs
  SigLIP 2 B 40.7 / So400m 48.1; ONNX encoders from the HF repo in
  `~/.local/share/flicker/models/mexma-siglip2`, sha256-checked): `scripts/wallpapers/clip.py`
  (uv script: onnxruntime/numpy/pillow/tokenizers) = a JSON-lines server (index / query /
  similar / forget / stop), vectors fp16 in `<thumbCache>/clip/`, image encoder loaded only while
  indexing, quits after `semanticIdleSec`; `services/WallpaperSemantic.qml` starts it on demand
  (outbox until started), indexes all thumbnails after the warm-up goes idle (niced, seconds per
  image on a laptop CPU — physical-core threads beat SMT ones, int8 quantize gave nothing: the
  export is already quantized; resumable: saved every 16), not on battery. Carousel: "? text"
  (debounced `semanticDebounceMs`, stale answers dropped by seq) and "~ name" / Ctrl+F = similar,
  best `semanticTop` by score, the best match centred (`rankReset`); pills "Searching…" /
  "Indexing n / m". Text encoder input is fixed 1×32 (padded); its attention pooling ignores
  the mask — queries are encoded one at a time. Verified: standalone protocol test, Russian
  queries on named thumbnails ("кот" → 3 cats, "машина" → 3 cars), live "? кот" + Ctrl+F.
  Hidden files are indexed too (same vector hidden/unhidden — the key ignores the dot), visible
  ones FIRST (hidden ones can be the bulk of a folder), or skipped with
  `semanticIndexHidden: false` (panel: General); the hidden-view mode filters BEFORE ranking.
  Panel action row "Search index" (row kind "action"): Run now = `forceIndex()` (ignores the
  battery gate, not stopped by unplugging), Stop = `stopIndex()` (`userStopped`: automatic runs
  stay off until forced again or the shell restarts); value = live "Stop · n / m" / "Run now ·
  N indexed" — N read from `<thumbCache>/clip/keys.json` (FileView, watched), the server may be
  down.
  Ctrl+S in a "? " / "~ " view freezes the ranked list into spec `{filter: "paths", paths}`
  (`WallFilter` "paths" keeps that order) — the slideshow re-resolves synchronously and could
  not wait for the model.
  qsBlue/cardBlue spring to a new accent per channel (`components/
  SpringColor.qml`: r/g/b/a on Springs, clamped). Settings panel = Ctrl+I in the carousel:
  `WallBody` blur-fades carousel ↔ `WallSettings` (two-column grid of `WallSettingsList.ROWS`:
  bool / choice / reset; focus plate springs; keys in `WallKeys.settingsKey`, a click changes a
  row; a dot marks a value that differs from config.json). Values = `Wallpaper.cfg` =
  config.json `launcher.wallpapers` + `overrides`, persisted in wallpapers.json `settings` —
  config.json is NEVER rewritten by the shell (JsonAdapter would dump every default);
  `resetSettings()` drops the overrides. Readers use the merged cfg (plugin `c`, services,
  QS slideshow card). Verified with wtype: change → override saved, reset → `{}`.
  The live preview uses `previewEffect` ("same" = the apply `effect`, default) for
  `previewDurationMs`: with a fade preview the picture is ALREADY on screen at Enter, so the
  apply transition (picture → itself) was invisible and the effect setting "did nothing" (user).
  Panel = two tabs (`WallSettingsList.PAGES`: Transitions | General, PgUp/PgDn or a click,
  pages blur-fade), rows = `WallSettingRow`. Look (Oct 2026, iOS Settings): segmented control
  (thumb springs), rows in two grouped `cardBg` cards with inset hairlines and a light rim
  (`components/CardRim` (was WallCardRim): filled slivers with vertical gradients — top edge round BOTH top corners,
  bottom edge only half way round, to 45°; Shape has no stroke gradients), dark icon tiles
  (`Theme.wallSettingsIconTop/Bottom` gradient + the same `CardRim`) with the glyph in the row's `tint` (a Theme colour name), value + selector glyph / iOS switch (qsGreen),
  focus = `Theme.wallSettingsFocus` highlight springing inside the cards; everything snapped to
  whole pixels (fractional row heights put NativeRendering text + 1px rims on half pixels), the
  icon tile size follows the row height's parity (34 in 45 → 1 px low; now 35, exact), tile
  glyphs use `renderType: Text.CurveRendering` (NativeRendering hinted the icon font into blocky
  strokes) placed at the EXACT fractional centre — floor()-snapping a vector glyph read as
  shifted left; measured on screenshots (user OK'd them): ink bbox within 0 / +0.5 px; rows have their OWN
  height (`settingsRowHeight`, WallSettingRow implicitHeight — they used to stretch to fill the
  page: 45 px on Transitions, 63 on General) and the body follows the page
  (`WallSettingsList.panelHeight`, incl. `settingsCardPadding` above/below the rows inside each card), so the island springs on Ctrl+I and on a tab
  switch (the carousel inside stays at `cardHeight`; `LauncherMetrics.maxHeight` counts
  `maxPanelHeight`). Every wallr effect + alias, and every effect
  parameter (`effectEasing/Origin/Angle/Direction`, `wipeSoftness`, `waveFrequency/Amplitude`,
  `fadeFrom/To`; "" = flag left out → wallr default) via `WallrArgs.params(cfg)` for apply AND
  preview; wallr accepts all flags with any effect (checked against a missing file). Testing
  the panel: NEVER press "Reset to config" — it wiped the user's own overrides once (restored
  by hand from the printed state).
  Verified via IPC + log only (centre on current wallpaper, thumbs, video init); visuals
  and keys NOT checked — the user checks visuals themselves (asked: no screenshots).
- Stash transcription (Oct 2026, user): WhisperX speech-to-text of tray audio / video.
  `services/Transcribe.qml` = child of Stash (`stash.transcribe`, Stash gets `events` from Shell):
  FIFO queue, ONE file at a time, `stateOf(path)` ""|queued|running|done|error, result JSON
  `cachePath("transcripts")/<md5(path)>.json` (`known` = cache scan at start + finished runs;
  stale if a same-named file replaces it → the view's re-run button). `scripts/stash/transcribe.py`
  (uv script, whisperx 3.8 on the PyTorch CPU index via `[tool.uv.sources]` — no CUDA assumed;
  protocol on a dup of fd 1, every library print goes to stderr; progress parsed from WhisperX's
  "Progress: N%" prints, weighted transcribe/align/diarize). Run = uv offline first, online retry
  only when it died WITHOUT output. Bar event key "transcribe" (transfer glyph + progress, hold).
  All settings in `Config.transcribe` (model, language auto|code, device, computeType, batchSize,
  threads, vad, align, diarize + hfToken ("" = $HF_TOKEN / HF login) + min/maxSpeakers, nice,
  paragraph joining, saveDir "" = the stash). UI: tile button (behind the trash, audio/video only)
  → `TranscriptView` (stash view "transcript", payload.file, fixed `stash.transcriptWidth/Height`):
  paragraphs WITHOUT timecodes (user; copies never carry them), click = copy, swipe-up over a
  paragraph forwards close; footer Copy all / .srt / Save (`TranscriptText.js`; writes go through
  stdin, never argv — an hour of text passes the 128 KB exec-arg limit). Tile: progress bar while
  queued/running, text badge when done. IPC `island stashTranscript <path>`.
  Verified: script on a real 16 s voice (small, ru, aligned), view render from a hand-written result
  + the running state. NOT tested: large-v3-turbo speed, diarization, copy/save clicks, the tile
  button (mouse), queue of several files.
- Session menu (Oct 2026, pShell `modules/session` port): `services/Session.qml` (Shell → Island
  `session` → services map) + `modules/session/` (SessionModule / SessionButton / SessionActions.js
  catalog: lock, logout, suspend, hibernate, reboot, poweroff). One row of bare glyph buttons, no
  labels (user: per-button tiles + title looked clumsy) + ONE flat selection plate springing
  between them (no rim/shadow, VelocityDeform stretch in flight like the OCR panel, radius = radius − padding, Theme.sessionPlate → accentRed when armed); idle
  glyphs dimmed (`idleOpacity/idleScale`), selected white, armed + GlyphBump; island radius `session.radius` (user: less round).
  Destructive actions arm on the first press, run on a second within `confirmMs`.
  The service runs `actionDelayMs` after the module closed; lock = LockScope, others =
  `Config.session.commands` (logout keyed by `Detect.backendName`: niri/drift/hyprland/default);
  suspend/hibernate lock first + `lockSettleMs`. Exclusive keyboard (←/→/Tab, Enter/Space, Esc =
  disarm, then close). IPC `island session`; in QS it is NOT a card: `QsRailButton` (power disc)
  sits in the tab-rail column, top = island radius (where the corner rounding ends, user), `quicksettings.sessionButton*` —
  `QsMetrics.railWidth` keeps the column even with one page, `railHeight` reserves the button
  slot top AND bottom so the tab icons stay centred. Verified via IPC + wtype + grim: render, arrow selection, Esc close. NOT
  tested: the actions themselves, the armed state, mouse.
- SYSTEM UPDATES (Oct 2026, user design): module `updates` (`modules/updates/UpdatesModule.qml`) +
  `services/Updates.qml` + `scripts/updates/update.sh`. Opened by a tap on the pending-count events,
  the `pacman` status drop (`open: "updates"`), IPC `island updates` (toggle). Idle = pending list
  (`checkupdates` + `yay -Qua`, repo / AUR sections) with TWO runs (user): «Репозитории» =
  `pkexec pacman -Syu`, «Всё» = `yay -Syu --sudo pkexec` (repos first, then AUR — AUR alone before
  the repos would build against stale libs / pull a partial upgrade; NEVER add `yay -Sua`). One
  button when one side is empty. Root ONLY via pkexec → the island's polkit prompt; NO polkit rule
  to cache the password (user). The run is NOT a shell child: tmux server `-L flicker` session
  `update` (a Quickshell Process dies on every hot-reload = pacman killed mid-transaction), started
  under `systemd-run --user --scope` (the shell lives in driftwm.service, KillMode=control-group: a
  compositor crash would kill a tmux left in that cgroup), its pane runs `SHELL=/bin/bash` (script -c
  uses $SHELL = fish here) `script -qfec <cmd> $XDG_RUNTIME_DIR/flicker/update/log` (pty for prompts / progress;
  the log has a "Script started/done" header + ANSI + \r redraws — `Updates.clean()` strips them).
  Exit → `status` file (`exit= reboot= pacnew= mode=`; reboot = /usr/lib/modules/$(uname -r) gone).
  Service polls `update.sh poll` every `updates.pollMs` while running, once at creation (adopts a
  run after a reload) and on every module open (`viewers` change); `lines` is reassigned only when
  it changed, and the log is ONE StyledText in a Flickable (a ListView over a fresh array rebuilt
  itself and lost the scroll every poll; follows the end unless scrolled up). checkupdates failing
  (exit ≠ 0/2) → `list` prints "error repo" → `listError` («Не удалось проверить», never a fake
  «Обновлений нет»). Text password prompts are never answered from the island (terminal only); no session + no status + a log = interrupted (exit -1). Prompt detection on
  the log's partial last line: `[Y/n]` at once → Да / Нет, other `==>`/`:`/`?` lines once the log
  size stood still a poll → «По умолчанию» (Enter); answers = `tmux send-keys`. «Терминал» =
  `kitty bash update.sh attach` (a client attached at exit keeps the pane until Enter). Nobody
  viewing (`viewers`) → events `updates:ask` / `updates:failed`, and `updates:reboot` after a kernel
  update, all `open: "updates"`. A polkit prompt over the module returns to it (`Island.polkitReturn`).
  The `pacman` status feed is on for the whole island run (yay builds without db.lck), text «Ждёт
  ответа» on a prompt. pacman busy without an own run (terminal) → the module shows the tail of
  /var/log/pacman.log. Verified live with a fake run in the same tmux session (prompt, answer,
  done + notices); a real -Syu NOT run by the agent.
- Polkit agent (Oct 2026, refs: DMS PolkitService, end-4 ii, caelestia): `services/Polkit.qml`
  (Quickshell `PolkitAgent` in a Loader, `Config.polkit.enabled`; ONE agent per session —
  a second Flicker / polkit-gnome just fails to register) → `started` opens module `polkit`
  (`modules/polkit/`) on the focused output. Service keeps a `request` snapshot + `phase`
  (idle|input|checking|success) + `failCount` (field shakes via SpringAnimation). AuthFlow
  restarts PAM by itself after a wrong password; switching `selectedIdentity` cancels+restarts
  (`switching` swallows that failure); `preferCurrentUser` picks $USER over root (DMS).
  Island: Exclusive keyboard while open, `polkitHolds` blocks every other openModule (OSD,
  flow cards queue), closeModule (swipe up) = cancel, success holds the tick `successHoldMs`.
  Height content-fitted (preferredHeight), radius = padding + buttonHeight/2.
  pam_faillock lockout ("(N minutes left to unlock)" in supplementaryMessage) is latched as
  `lockUntil` + 1s countdown → the password pill turns red with «Заблокировано · N мин» inside
  (input `readOnly`, NOT disabled — a disabled TextInput drops Esc). Verified live during a real
  lockout. Don't burn wrong passwords testing: 3 fails = 10 min lock (`faillock --user $USER`).
  In-field texts (placeholder / checking / lockout) are three `FadeBlur` layers; the lockout
  string is split at `%1` (`lockPrefix` static + `lockValue` in `RollingText`). Status line
  blur-fades in, keeps its last text + height until faded out, then collapses (Column `move`
  springs). Haptics `Config.haptics.polkit`: deep on a failure that answers a submit, release on
  success. Spring-driven colour alphas are clamped (overshoot → "setAlphaF: invalid value").
  Field states testable without PAM in a scratch FloatingWindow harness (symlinked dirs,
  `grabToImage` frames) — verified crossfades + 4→3 roll that way.
  Verified live with `pkexec /usr/bin/true` + wtype: render, wrong password → error, Esc →
  "Request dismissed". Success path NOT tested (needs the real password).
- Teleprompter (Oct 2026, user: in the island, hiding from screencasts DROPPED): service
  `services/Prompter.qml` (Shell → Island `prompter`, IPC `prompter`) + module `modules/prompter/`
  (`PrompterModule` + `PrompterBlock` per markdown block) + launcher plugin `!prompt`
  (`plugins/prompter/`: files under `prompter.dir`, newest first, + "from clipboard").
  `PrompterParse.js` = md subset → blocks of styled pieces + flat word list; notes ([brackets],
  <!-- -->, > quotes) and code are NOT spoken (excluded from alignment, drawn blue-italic).
  Each block = read-only RichText `TextEdit` (`enabled: false` → press-transparent;
  `positionToRectangle` gives the cursor word's line → scroll spring puts it on `readLine`);
  only the block holding the cursor rebuilds its HTML (`localCursor` clamp). Rich-text CSS gets
  OPAQUE colours (Theme `prompter*`). Body = frost path with `Theme.prompterBody` (dark glass,
  `Island.frostTint` latched per module; "prompter" in `effects.frostModules`).
  Voice: `Dictation.startFor("prompter", lang)` — `sink` "prompter" = no wtype, no Refine/LLM, no
  layout restarts, dictation indicator hidden, the dictation key (`toggle`) ignored meanwhile;
  lang = script alphabet (`detectLang`) unless `prompter.language`. `PrompterAlign.js` = local
  Smith-Waterman of the last 8 heard words (finals + live partial) vs the spoken script: fuzzy
  words (Levenshtein + ru stem bonus), short words weigh little, gap / trailing-unmatched costs;
  local window (−8/+60, distance-penalized, forward-only except a strong re-read) → after 3
  unmatched heard words a WHOLE-script search (≥3 matched, unique by `uniqueMargin`, throttled
  `globalThrottleMs`) = off-topic / skipped-section recovery; 6 unmatched = `lost` ("searching").
  Node harness (clean / ASR noise / off-topic / skip / restart, 4000-word perf ≈11 ms in node):
  load the .js with `.pragma library` stripped. Island: the prompter is a SESSION — a module
  opened over it (launcher, QS) returns to it on close (`prompterHere`), OSD is suppressed while
  it shows, flow cards queue (moduleOpen), moduleIdle never closes it; closing it (swipe up, Esc)
  = `prompter.close()` (mic off, position saved). Position per file + last file in
  `statePath("prompter.json")`; the file is watched, an edit re-locates the cursor by its last
  read words. Verified live (Oct 2026): render, manual move, and the user reading the demo aloud
  — tracked to the end incl. ASR errors ("покурим"/"поговорим"). NOT tested: auto mode, keys,
  wheel, footer pills, launcher plugin, clipboard, multi-output hand-over. Known: viewport edges
  are a hard clip (no soft fade on the translucent body — MultiEffect masks are binary).

- Indicators polish (Oct 2026, user decisions). Bar row = [privacy | music | dictation |
  clock | timer]; event glyph / text are NOT in the row: pinned to the island's left / right edges,
  and the island grows by the wider half on BOTH sides (`IndicatorLayout.eventSide`, added twice
  in `Island.barFittedWidth` and the eviction budget) — the main row stays centred on screen
  while an event shows (user). The text slot is sized ONCE per event from the widest of all its `texts`
  steps and latched (grows only, never shrinks until the next event) — the island must not
  resize after it spread, e.g. on the "95%" → "1 h 25 min" roll (user).
  PRIVACY DOT (`indicators/PrivacyDot.qml`, was Microphone.qml) = ONE dot, colour by the most
  sensitive capture (`services/Privacy.qml`): screen share red > camera green > mic orange,
  never several dots; hover label = consumer app. Untracked PipeWire nodes have EMPTY
  `properties` → kinds from `node.type` (`PwNodeType.VideoSource`) + `node.name`: a Video/Source
  named with `privacy.cameraPrefixes` (v4l2_input/libcamera_input) is a camera, any other one a
  screencast (xdpw "xdpw-stream", niri's cast). Camera also = any process holding /dev/video*
  (`fuser` poll `cameraPollMs`, pipewire/wireplumber ignored; browsers use V4L2 directly).
  Verified live: ffmpeg on /dev/video0 → green "ffmpeg"; a gst `pipewiresink mode=provide`
  Video/Source named xdpw-stream → red. NOT verified: consumer names via PwLink (gst
  pipewiresrc got "target not found"), a real portal screencast.
  EVENT INDICATORS (`services/Events.qml`): one at a time, FIFO with the notification-flow
  timing (`events.showMs` 5 s alone / `showQueuedMs` 3 s with more queued, an arrival shortens
  the visible one; `gapMs` collapse between two). Glyph at the far LEFT (`EventIcon`, `eventIconSize` 22, `eventGap` 28 — user, Oct 2026; while an event shows (or is queued) the row recedes: `IndicatorLayout.rowSurface` BlurSurface to `eventRowOpacity`/`eventRowBlur`; pressed to the edge: same gap to the left edge as to
  top/bottom = `pull` px into edgePaddingMin — event glyph ONLY; both halves add `eventGap` toward the row), text at
  the far RIGHT (`EventText`, `text` may be a function → live inside the binding). Event =
  {key, icon, text, color (Theme property NAME; tints the glyph; text is neutral `Theme.eventText` unless `textColor` — user, Oct 2026), family ("nerd" = Theme.nerdIconFamily)}; same
  key replaces in place, `cancel(key)` drops it. Sources (Shell): `EventCharging` (UPower
  onBattery: plugged = bolt join, pulled = bolt break; colour = `Battery.levelTone` (the right arc's
  rule, shared; event `color` may be a function → live); `texts` steps = percent, then
  after `events.textStepMs` the time to full / to empty drum-rolls in via RollingText; EventText
  width = per-char advances of the TARGET text), `EventBluetooth` (new connected device → device glyph +
  Battery1 % / name), `EventUpdates` (once, `updatesDelayMs` after start: pacman count, then AUR;
  glyphs from the user's show_updates: md-pac_man f0baf and f4a2 = oct-smiley in Nerd Fonts v3).
  Event `open: "<module>"` (+ `openPayload`) = tap opens that island module on the CLICKED island
  (IndicatorLayout.requestModule; `tap` wins when both); EventUpdates' counts open `updates`.
  GLYPH LIBRARY (Oct 2026, user: "draw every one, Apple-style, same kind of animations"; services
  for the new events NOT built yet — only the glyphs): `indicators/glyphs/` = every drawn glyph +
  `GlyphBase.qml` (size/color/args/theme/ready → `begin()` once; `p(key, def)` reads
  `Config.glyphs.<glyphName>` then `glyphs.common`; palette fillTop/Bottom from the tint,
  deviceTop/Bottom + ink from Theme `glyphDevice*`/`glyphInk`), `GlyphFill` (gradient path +
  white sheen), `GlyphLine`, `GlyphWaves` (sound/signal arcs loop), `GlyphScreen` (bezel drawn
  along the perimeter + glass painted bottom-up + shine band), `Glyph.js` (rrect/ellipse/arcPts/
  rrectPts/trim/clipY/span/smooth), `GlyphRegistry.qml` (explicit Components; EventIcon looks up
  `event.glyph` there). Devices: airpods, airpodsMax (= headphones alias), speaker (HomePod mini),
  phone, tablet, laptop, watch, mouse, keyboard, gamepad, bluetooth (rune); events: lock (VPN),
  moon (focus, Theme `focusPurple`), transfer (`args.progress` or indeterminate), error, copy,
  pacman `args.food: "box"` (package installs). `HelloGlyph` = Apple-style first-run "hello" (NOT an
  event glyph, aspect × size wide): cursive Béziers sampled to a polyline, written by a timed trim,
  hue flowing along the word (stroke cut into `segments` pieces — no stroke gradients); not wired
  to a first-run flow yet (user: animation only). EventBluetooth picks `drawnGlyph(icon, name)` —
  name first ("AirPods Max"/"AirPods"/"Buds"/"HomePod"; BlueZ reports both AirPods as
  audio-head*), then the BlueZ Icon kind. Previews: IPC `island glyphDemo <name>` (`parcels` =
  pacman with boxes) / `glyphDemoAll`; dev window `quickshell -p dev/glyphs/shell.qml` (all at
  64 px, replay every 7 s, click = replay). Verified: harness frames (reveals step by step) +
  every glyph in the live bar at 18 px (all readable). Traps hit: GlyphFill colours are
  `colorTop/colorBottom` — `top`/`bottom` are FINAL Item members ("Cannot override FINAL
  property" took the whole config down); inline `component` blocks do not see the file's ids
  (two-of-a-kind parts are Repeater delegates instead).
  ANIMATED GLYPHS start only when EventIcon binds `ready` (its FadeBlur p ≥
  `indicators.eventGlyphStartAt`): starting at creation ran short reveals under the blur-fade-in
  of a FRESH icon (invisible), while an icon surviving the gap was already visible → "sometimes
  the animation shows, sometimes not" (user). EventIcon sets `args` BEFORE binding `ready`.
  ANIMATED GLYPHS (user: own drawn icons, animated): event `glyph: "<name>"` → EventIcon loads
  the Component from its `glyphs` map (font `icon` = fallback); `indicators/PacmanGlyph.qml`
  (pacman updates): reveal = line grows from the centre to the right, sweeps 330° clockwise
  while its start edge drops 30° (lower jaw); loop = dot scales+fades in on the right (SkipBtn
  entry), FLIES in at constant speed (timed linear `flyMs` — user: not a spring) to the body's
  live centre, jaws close behind it from `biteAt` of the flight, the eye (a HOLE in the body, even-odd —
  the reveal stroke is a separate ShapePath so the eye gets no stroke dot) squeezes
  shut with the jaw, body recoils left on a bouncy spring, dot swallowed (drawn under the body)
  once it arrived AND the jaws shut, jaws reopen. Bites come in pairs (`series` 2, `pauseMs`
  between them), then a `restMs` break. Look = the wallpaper-settings icon tile: vertical
  gradient fill (`lighter`/`darker` of the colour, dot too) + CardRim-style light rims on
  the sector's outer edge (top full, bottom to 45°; `Theme.glyphRimTop/Bottom`, stronger than
  the tile's — invisible on yellow otherwise); the reveal stroke fades out with the sweep.
  `indicators/GhostGlyph.qml` (AUR, follows pacman; user pick over smiley/box/gear): outline
  = ONE `PathSvg` string built in JS (head arc while drawing, then head + sides + rippling
  hem — fixed PathX element counts can't vary). Reveal head arc → sides drop + hem (2 small travelling half-waves) opens
  → eyes pop; eyes = HOLES in the body (even-odd ellipse subpaths in the same PathSvg; user:
  not white sclera + pupils), shifted toward the look; loop: feet `wave` (timed infinite loop),
  eyes look L/R (`lookHoldMs`), and on every other look-around the whole ghost STEPS sideways
  toward the look after `swayDelayMs` (user: a shift, not a tilt; looks L R L R…, steps on looks
  0 and 3 of 4 → first left, then right; `swayShift`). Motion (user: "nervous glances, leans
  in as if inevitable — fast start, then slows"): TIMED decelerating curves, not springs — eyes
  OutExpo `lookMs`, step OutExpo `swayMs`, return OutCubic `swayBackMs` (set imperatively before
  the change), glance holds random lookHoldMin..MaxMs. Logged the value: the curve WAS right, but
  a 2.5 px step fits the lunge into 2-3 frames and reads linear — keep the step ≥ ~4 px.
  While stepping it LEANS into the motion (user: rectangle -> parallelogram, not a rotation):
  a shear `Matrix4x4` about the bottom edge (hem planted, head leads by `leanShift`), `lean`
  set in stepTo, builds up on a soft spring (leanIn*, user: not so fast), held leanHoldMs, then
  straightens on a bouncy one (leanOut*; Spring params swapped imperatively); the return
  leans the other way (`leanBack`). Hem
  corners rounded by a quadratic (`hemRound`).
  Tunables `Config.glyphs.ghost`. Verified frame by frame. A spring-driven dot in sync with the jaw hit
  the closing lips outside the mouth (user: "не в попад"). Shape CurveRenderer sector (PathAngleArc,
  clockwise degrees from 3 o'clock) with a round-joined stroke = the visible line at sweep 0.
  Phases hand over at `handoff` of the target, NOT onFinished (over-damped SpringAnimation
  creeps the last % for ~1 s). Tunables `Config.glyphs.pacman`. Verified frame by frame (grim).
  CAFFEINE (Oct 2026): `services/Caffeine.qml` (session `active`, IPC `island caffeine` toggle,
  debugState `caffeine`); every Island holds a Quickshell `IdleInhibitor { window: root }` bound
  to it. Toggling posts an event with `glyph: "coffee"` + `glyphArgs {drain}` (EventIcon passes
  `glyphArgs` to `item.args`; a NEW event key recreates the glyph Loader (`glyphFresh`) so the
  reveal replays even when the same glyph follows itself). `indicators/CoffeeGlyph.qml`: stroked
  wide cup (handle LEFT, `handleSide`) (walls rise from the bottom curve) + handle arc sweep, coffee inside behind a gap with a
  small travelling sine surface, poured in on an under-damped spring (slosh) / drained on off.
  Tunables `Config.glyphs.coffee`, `Theme.coffee`. Verified frame by frame (on + off).
  LOW POWER MODE (Oct 2026): `services/PowerMode.qml` (QS card `lowPower`, IPC `island powerSave`
  toggle, debugState `powerSave {available, active}`) = Quickshell `PowerProfiles` over the
  standard `org.freedesktop.UPower.PowerProfiles` D-Bus API (power-profiles-daemon / tlp-pd /
  tuned-ppd — never write sysfs/TLP directly: hardware-agnostic, no root). `active` = the LIVE
  profile is power-saver (TLP resets it on a power-source change); off restores the profile from
  before. No daemon (dbus-send ListNames/ListActivatableNames probe) → card "Unavailable". While
  active (user rule: no background heavy work, only what the user starts): thumbnail warm-up and
  semantic indexing are blocked outright (`powerSave` in their `allowed`, no override; the panel's
  forceIndex still runs), slideshow steps `paused` (separate from the carousel's `hold` Binding),
  video wallpapers paused (WallrClock), update check held, SystemUsage / Sensors poll `pollFactor`×
  slower — `Config.powerSave`. Verified live: tlp-pd → TLP SAV (max_perf_pct 60 → 40 → 60).
  AIRPLANE MODE (Oct 2026): `services/Airplane.qml` (QS card `airplane`, IPC `island airplane`,
  debugState `airplane {available, active}`) = rfkill (/dev/rfkill has a user ACL, no root).
  State from a long-running `stdbuf -oL rfkill event` (lists devices, then changes; no polling);
  `active` = every device soft/hard-blocked, so external blocks show. On: snapshot the unblocked
  type names + BT adapter power → statePath("airplane.json"), `rfkill block all`. Off: unblock
  only those types (no snapshot → all), then put the BT adapter back to its saved power (BlueZ
  powers it on after an unblock). `Config.quicksettings.airplane.dnd` (default false): DND on with
  it, off with it only if the mode set it. QML JS here has no object spread — use Object.assign.
  CHARGER BOLT `indicators/BoltGlyph.qml` (user pick: "the bolt breaks"). Appearance (user, after
  several rounds — strike line / swell / bloom all read abrupt): the bolt is PAINTED by a fill
  front (critically damped `reveal`; polygon clipped by the front's half-plane) DOWN from the top
  on unplug, UP from the bottom on plug-in, a light gradient band rides the front, then a soft
  neon flicker (eased `lit` dips + flares). Also fixed: a same-key event right after another
  reused the old glyph mid-loop (EventIcon now recreates it for every new event, not just a new
  key). `glyphArgs.mode`:
  break (unplug): after the appearance → crack along a
  BOLT-SHAPED top-to-bottom polyline (user: breaks into two thin bolts; vertical, not straight; the outline is split at the first /
  last crossing, the crack must cross it exactly twice) → halves TILT apart about the crack's
  bottom exit (left one left, right one right; user) on a bouncy spring; loop: halves drift toward each other (nearSep) and back, sparks flash in the gap when
  close. join (plug-in): halves appear apart → snap together → flash fuses the crack; loop:
  charge pulse. Mode is read a tick AFTER onCompleted (`Qt.callLater(begin)`): EventIcon sets
  `args` in Loader.onLoaded, which runs after the item's onCompleted. Tunables `glyphs.bolt`.
  Verified frame by frame via `eventDemo discharging|charging`.
  REAL plug-in (measured with the user, Oct 2026): TLP switches to AC (turbo, PCIe ASPM default)
  and the WHOLE compositor freezes ~0.5 s about 1.5 s after the event appears (a 492 ms frame gap
  mid-flicker; grim frames froze too; a ~117 ms gap at every AC change as well). Springs jump to
  their end → "no animation on plug-in" while IPC demos were perfect. Guard: a FrameAnimation
  watches frameTime during the appearance; a gap > `stallMs` replays it (≤ `stallReplays`).
  IPC `island chargerSim true|false` runs the REAL handler (cancel + post) without a cable.
  Sources ignore the first `startupQuietMs` (BlueZ/UPower populate async). Duplicate
  notifications dropped on arrival by `notifications.suppress` regex rules (default blueman
  "Connected…", Disconnected still shows). IPC `island eventDemo charging|discharging|bluetooth|pacman|aur|<text>`.
  Verified live: demo events render, FIFO 3 s / 3 s / 5 s with the gap. Events show only in the
  bar state (a module/Minimal hides them; their timers keep running).
  LOW BATTERY: right arc "wipers" (tempShell RadialSliderIcon connecting sweep) — fill sweeps
  level ↔ full, timed InOutCubic `arcs.wiperMs` (user exception like hideProgress), while
  `battery.low`; verified in a scratch harness (frames).
- STATUS DROP (Oct 2026, user design) = the third indicator kind, for LONG processes (events only
  inform and leave). `services/Statuses.qml` (one shown at a time: highest `priority`, or the key the
  user swiped to = `pinned` until it ends; entry {key, priority, color (Theme name | fn), progress
  (0..1 | fn | null = spinning), open "timer"|"transcript"|"stash"|""}) fed by
  `services/StatusFeeds.qml` (timer 100, recording saving 80, Shazam listening 70, transcription 60,
  LocalSend 50, wallpaper semantic indexing 10; toggles `Config.status.<feed>`). A feed announces
  (status + start event) only after `on` held `status.announceDelayMs` (timer: at once) — the
  semantic index wakes after every warm-up, finds nothing new and reports done instantly, which
  flashed the event (island spread for a split second).
  OUTCOME (user): exactly ONE of event / notification when a status ends. Notification = a result to
  act on later or an error worth keeping (recording saved → tap opens the file / failed; transcript
  ready → tap = `quickshell ipc -p <shellDir> call island stashTranscript` / failed; Shazam match
  (event only with `shazam.notify` off); LocalSend's own script notifications). Event = a plain
  result (Shazam no match / failed). Nothing = user's own cancel / discard, background work (index).
  Timer keeps its own finish (module + alarm). A notification outcome cancels the start event. A status starts with
  its EVENT tagged `status: key` (Transcribe / Shazam post theirs, feeds with `event` post
  "status:<key>"): while it shows the TEXT follows the glyph on the left (user; EventText `leading`,
  `IndicatorLayout.statusEvent` / `eventSide` = max(glyph + textGap + text, ring room)) and the ring
  sits INLINE in the island's right end rounding; when it leaves the island collapses and the drop
  splits off.
  `core/StatusDrop.qml` = body BELOW the island: circle + metaball neck (`components/Metaball.js`,
  Sato/varun construction, spread fades to 0 toward `breakDist`, cut below 0.15 — thinner rendered as a
  dotted hairline) from the ANIMATED island end; position springs to TARGET geometry; split = pulled
  `pull` px past rest until the neck snaps (`breakAt`), then recoils (`pulling`/`broken` latches);
  modes inline/out/hidden (module, Minimal, ticker: absorbed, r ≤ drop r)/none. Painted only while
  `live` (shown → until merged back): at shell start the geometry settles and the invisible drop
  springs across from near the left edge — it used to be seen flying in from the corner. Ring = 
  `indicators/StatusRing.qml` above the island (track = tinted remainder, so its turn shows; swap =
  one spring `k`: ring turns once in `lastDir`, track recolours, old arc squeezes into its start, new
  grows from it; sucked back in, the ring shuts by drop POSITION — `StatusDrop.squeeze`, shut at
  `closeAt` × touching distance — so it is closed before the merge (user: a faster reveal spring
  alone did not do it)). Battery arc wraps the drop (`Arcs.rightShift`). Tap = `Island.openStatus`, horizontal
  swipe = `Statuses.cycle`. The timer no longer sits in the row / on the music cover while
  `status.timer` is on (`Island.timerInDrop`): `Island.timerOwner` = a hidden (opacity 0) TimerHalo in
  the drop — its PerimeterProgress is the ringLayer shared element; the StatusRing hides the timer
  while it is away. Verified via IPC demos + grim frames: inline → split (neck), swipe swap, timer
  ring drop → module → back → split. NOT tested: mouse tap/swipe, real Shazam / transcription /
  LocalSend / saving / indexing feeds, multi-output.
- MORE EVENT / STATUS SOURCES (Oct 2026). Events: `EventNetwork` (Wi‑Fi joined / switched / lost,
  settled `wifiSettleMs` vs the last ANNOUNCED state; `WifiGlyph`, `args.lost` = arcs go out outer
  first), `EventAudioOutput` (`pactl subscribe` → debounced `pactl -f json list sinks`, signature
  default-sink|active-port — a jack plug only switches the PORT; bluez sinks skipped = EventBluetooth's;
  glyph headphones/display/speaker/laptop, texts name → live volume), `EventBattery` (full = FullyCharged
  or ≥ charge limit (`battery.chargeLimit`, 0 = sysfs charge_control_end_threshold, none → 100),
  critical ≤ `battery.criticalPercent`, once per charge / discharge; `BatteryGlyph`), `EventDisplays`
  (Quickshell.screens diff; `DisplayGlyph`, `args.off` = TV switch-off), `EventDrives` (`udevadm monitor`
  block → `lsblk -J`, hotplug/rm + fstype; `DriveGlyph`, `args.eject`). Event `tap` (function) = NEW:
  IndicatorLayout puts MouseAreas over both event halves ONLY while the current event has one (drive:
  mount via udisksctl if needed + xdg-open; finished download: open the file). Statuses (StatusFeeds):
  `lens` (CaptureActions.lens is a Process now, `lensBusy`; failure = `error` event, no notify-sends),
  `pacman` (`services/PacmanWatch`: db.lck polled, count = ALPM lines pacman.log gained; end = event
  "N packages updated", pacman + boxes), `download` / `modelDownload` (`services/DownloadWatch` +
  `scripts/status/downloads.sh`: .part/.crdownload in the XDG download dir, HF `.incomplete` / torch
  `.partial` under `status.modelDirs`, only partials touched within `downloadsFreshMin`; spinning, text
  name · bytes; finished browser file → event, tap opens), `refineWarmup` (`Dictation.refineWarming`),
  `wallpaperDupes` (announce delay 4 s: warm runs ~2 s), `wallpaperWarmup` (`Wallpaper.warmup` progress).
  recordSaving now has PROGRESS: record.sh prints `progress <0..1>` after stop (finishers, then the
  concat — a re-encoding concat via ffmpeg `-progress pipe:1` vs the ffprobe'd total) →
  `Recorder.saveProgress`. IPC `eventDemo wifi|wifiLost|output|full|critical|display|displayOff|drive|
  driveOff|downloaded` run the REAL announcers. Verified on the live instance (grim frames): every demo,
  a fake growing `.part` → status + drop split + "Downloaded" event. NOT tested: real Wi‑Fi roam, jack
  plug, real monitor / USB stick, pacman (needs root), Lens, record save progress, model
  downloads, refine warm-up, taps (mouse).
- Timer (Oct 2026, user design after an iOS Live Activity reference): `services/Countdown.qml`
  (NOT `Timer.qml` — would shadow QtQuick's Timer in that dir; phase idle|running|paused|done,
  `progress` remaining 1→0 refreshed every ~0.5 px of a `perimeterPx` outline (16 ms..1 s),
  alarm = `pw-play alarmSound` every alarmEveryMs ≤ alarmMaxSec, `openOnFinish` →
  `Island.showTimerDone`) + `modules/timer/` (TimerModule / TimerRuler / TimerButton; island
  `modules.timer` 380×172 r40) + bar ring `indicators/TimerRing.qml` (LEFTMOST in the row) + QS
  card `timer` (real now, tap = module). Module = ONE spring driver `k` (0 setup, 1 live):
  setup = minute ruler (EQUAL orange ticks, one per minute — a tick arriving on the triangle
  flashes `Theme.timerTickFlash` near-white (fast spring in, flashHoldMs, soft spring out); ticks
  RIGHT of the triangle blend to `Theme.timerTickDim` (trap hit: a tick prop named `right` =
  "Cannot override FINAL property", whole shell failed to load — renamed `past`); number
  every 5, 0..120, equilateral triangle pointer
  whose top sits `triangleOffset` BELOW the module centre — the ruler is placed by it (user);
  motion/wheel/touchpad/speed levels copied from the wallpaper carousel; keys ←/→ ±1 (Shift
  ±5), ↑/↓ ±5, Home/End, Enter/Space start|pause, Delete cancel, Esc; numbers orange too) +
  "Start timer" orange text PILL bottom-left (user: text, not a play glyph; TimerButton `label`,
  width springs pill → disc when it turns into pause) +
  rolling time bottom-right; live = time centred (same item, scaled), pause left, ✕ right, bell +
  end time above, "Timer" below, perimeter progress. Keyboard: Exclusive in setup, OnDemand live.
  Cancel = back to setup; done: ✕ / closing = dismiss (alarm off), left = restart.
  Ring and perimeter are ONE item (`components/PerimeterProgress`: rounded-rect outline, radius
  = size/2 → circle; `gap` = centred free top part — module: `perimeterGap` (1/3) of the island
  width, user; ring: 0 = closed; the outline runs clockwise from the gap's right edge, the spent
  part is eaten from its left end; gap/lineWidth/radius are in the shared contract;
  inset from the island edge = the line width). The ring OWNER is `indicators/TimerHalo.qml`
  (contract + restoreShared). With `indicators.musicTimerRing` (default) Music.qml is ONE
  music+timer indicator (row slot right after the stand-alone timer's, i.e. leftmost): the
  halo's OUTER edge = the plain cover's size (user), the cover shrinks inside it by
  `musicTimerRingGap` + line, and a
  player closing / appearing only scales the cover out / in while the ring springs between
  "around the cover" and `timerRingSize` — no indicator swap (user). TimerRing is only used
  with musicTimerRing off. On the cover with a timer: hover no longer opens the player, tap =
  player (no player: timer), press + drag down past `musicTimerDragPx` = timer. Verified: ring
  around the cover, stand-alone ring without a player, IPC flights; NOT seen: the live player
  close/appear morph, mouse paths. flown by a SECOND TransitionLayer (`ringLayer`, payload `sharedRing`) while
  the clock flies into slot "time" (ClockPlate contract `timer`, `hideLanded`: the docked label
  hides, the module rolls its own digits). `Island.openTimer` launches flights only from the
  visible bar; otherwise the module draws its own copies, and `sendTimerHome()` ADOPTS them on
  close (`TransitionLayer.adopt` = dock into the slot with no flight, then returnHome) — so the
  countdown always flies into the clock and the perimeter folds into the ring. TransitionLayer
  changes for it: hidden elements refresh their props from the slot before flying home (else the
  stale landing text flew back), returnHome keeps `slot.docked` (the module re-showed its own copy
  → doubled in ContentSwap's ghost; fixes the player cover too), dockHome clears the slot
  anchors. Cancel with the ring docked: `ringLayer.abort` via Qt.callLater — called inside the
  phase-change chain it logged "QQmlVMEMetaObject: ... invalid context".
  Verified live via IPC + wtype + grim frames: setup render, start morph, flights both ways
  (incl. adopt), pause, done (auto-open, sound, dismiss), keys. NOT tested: mouse (ruler wheel /
  touchpad, number taps, buttons), the QS card, multi-output.
- Keyboard pill (Oct 2026, macOS input-source / Caps Lock indicator, ref solium
  `crates/solium/qml/Solium/KeyboardPill.qml` + `lua/keyboard_indicator.lua`). User: NOT in the
  bar — under the TEXT CARET, else under the mouse pointer; background = wallpaper accent
  (`Theme.wallAccent`, SpringColor; ink by luminance); moves on springs; clamped inside the screen
  (`keyboard.edgeMargin`), above the caret when no room below. Parts: `services/KeyboardIndicator`
  (policy: `what` = "caps" held at the caret / `capsPointerMs` at the pointer, "layout" for
  `layoutShowMs` after a switch; Caps Lock = keyboard LED `/sys/class/leds/*::capslock/brightness`
  polled `capsPollMs` — no compositor reports locked mods, the kernel change raises NO inotify),
  `services/Caret` + `scripts/keyboard/caret.py` (stdlib raw-Wayland client = the seat's INPUT
  METHOD (zwp_input_method_v2, no keyboard grab) with one never-mapped input-popup surface:
  smithay forwards every text-input-v3 cursor rectangle to it as `text_input_rectangle`, in the
  focused SURFACE's local coords; global = focused window rect from `Compositor.windowRects` (+
  zoom) + rect. Client-side margins (GTK shadow / resize border) shift it right/down by a
  PER-WINDOW amount (zenity text window 10/20, dialog 20/20) that nothing exposes (IPC has only
  geometry; AT-SPI GTK4 extents are container-relative, Text iface errors) → measured:
  `services/CaretCalibration` + `scripts/keyboard/calibrate.py` = 7 `driftwm msg screenshot
  window --id N -o -` captures (exactly the geometry, in memory) 200 ms apart, their difference =
  the blinking caret, offset = rect centre − blink centre; once per window after the caret rests
  `calibrateDelayMs`, discarded if the rect moved; window offset doubles as the app's first guess;
  session-only; drift only; `keyboard.caretOffsets {app_id: [dx,dy]}` overrides. Verified: marks
  land on the caret in both zenity kinds, live run → `#35 20 20`, pill centred under the caret.
  NEVER start a second caret.py while the shell runs: it took the seat's input method from the
  live one (live helper → `unavailable` until its 60 s retry). fcitx/ibus running → helper exits 3, pointer only.
  While an island holds the keyboard Exclusive (`Island.takesKeyboard` → `IslandRegistry`) the
  caret is ignored (it is relative to the island surface)), `modules/keyboard/KeyboardOverlay`
  (per screen: Overlay surface, EMPTY mask, mapped only while shown; the capsule CENTRE springs —
  a target reading the animated width restarts the spring per frame) + `KeyboardPill`. Pointer:
  nothing reports it → `probe()` maps a second full-screen INPUT surface for a moment, the
  compositor sends wl_pointer.enter ~17 ms after the map (verified on driftwm), `pointerSeen`
  unmaps it; the pill shows only after the probe. Native text on a transparent surface leaves
  subpixel colour fringes → `RollingText.renderType: Text.QtRendering`. Test: `temp/vkey.py`
  (uinput keyboard, keycodes; with xkb `grp:caps_toggle` `42+58` = Shift+Caps = Caps Lock,
  `58` = layout switch, `30` = a, `led`) — the whole sequence in
  ONE vkey run (a vkey device leaving resets the compositor's Caps Lock); `zenity --entry` for a
  caret; one-shot Timer: `running` is still true inside onTriggered (own flags). IPC
  `island keyboardDemo layout|caps`, debugState `keyboard`. Verified live: caret follow while
  typing, caps→EN→caps at the caret, launcher → pointer, bottom-right corner clamp. NOT tested:
  niri (windowRects there NOT live-tested), multi-output, zoomed drift canvas.
- Shazam (Oct 2026): `services/Shazam.qml` (Shell → Island `shazam` → services map, IslandIpc
  `island shazam` = listen / cancel) runs `scripts/shazam/recognize.py` (uv script, shazamio +
  audioop-lts, Python <3.14 — shazamio-core has no 3.14 wheels): parecord raw 16 kHz mono,
  `source` auto = default MONITOR, switching to the mic when the first `--probe` s peak below
  `--silence`; asks Shazam every `stepSec` (last ≤12 s, the reader keeps draining the pipe
  meanwhile) up to `maxSec`; JSON lines listening/found/none/error; cover → `cachePath("shazam")`.
  Run = uv DIRECTLY (offline, one online retry if it died silently): uv forwards SIGTERM, python
  dies, parecord gets SIGPIPE — a bash wrapper kept them alive on cancel. Streams
  `flicker_rec_shazam` (monitor, hidden from the mic dot) / `flicker_shazam_mic` (mic, dot
  shows). Event key "shazam" with the new `hold` flag (Events: no life timer until a same-key
  non-hold replacement) + `indicators/glyphs/ShazamGlyph` (breathes while `args.listening`, pops
  on `found`; EventIcon now BINDS `item.args`, so in-place updates reach the glyph). Match =
  notification via notify-send (`-A default=Open` → xdg-open shazam.com, `copy` → wl-copy) +
  history in `statePath("shazam.json")`. QS card `shazam` (QsCatalog, hidden by default).
  QV4 has no `String.trimEnd` (threw in the event text). Verified live via IPC: listening event,
  mic fallback + privacy dot, real matches, notification with cover in history, cancel. NOT
  tested: the card tap, the notification actions.
- MPRIS multi-player: `services/Players.qml` picks `active` dms-style (prefer a playing
  player, remember the last playing one, a paused player beats registered-idle ones at
  cold start). Plain `players[0]` picks early-registrants like Telegram (registers
  Stopped with stale voice-message metadata) over the actually playing app.
  Cover art: `Players.artUrl` is NEVER a remote URL — http(s) art (Spotify i.scdn.co, YouTube
  thumbs) is fetched with `curl -4` into `cachePath("art")/<md5>` (`Config.mediaArt`), Qt's
  network Image loader stalled on a network with broken IPv6 (Spotify covers never showed,
  no warning logged; a fresh process loaded them). Raw value = `remoteArt`.

- i18n (Oct 2026, user: source language ENGLISH): `config/I18n.qml` (pragma Singleton next to
  Config, so `import "<rel>/config"` brings both). EVERY user-visible string = `I18n.tr("English")`
  (+ `.arg()` for `%1`), plurals `I18n.trN(n, "%1 file", "%1 files")`, dates via `I18n.locale`
  (`toLocaleDateString(I18n.locale, I18n.tr("dddd, MMMM d"))` — the format pattern itself is a
  key; ru `MMMM` = genitive, `standaloneMonthName` = nominative; `I18n.capitalize` for ru's
  lowercase names). Catalog `assets/i18n/<lang>.json` = flat `{English: перевод}`, plural entry =
  array in the language's CLDR order (ru one/few/many, rule in `pluralIndex`), missing/empty →
  English. Language = `Config.i18n.language` (`"auto"` = Qt.locale(), default). Catalog watched; switching language
  re-evaluates bindings live (tr() reads `table`) — verified ru↔en on the dashboard. Never hard-code
  non-English UI text or keep translated strings in services: return English keys and translate
  at the display site (`Weather.desc`, `QsCatalog` titles) so a switch follows without a refetch.
  Data in a language: the weather city is geocoded with `language=I18n.lang` (resolve key =
  location|lang, re-geocoded on a switch); auto-by-IP (ipinfo) names are English only.
  Strings passed to shell commands go through `shq()` (translations may contain quotes). NOT
  translated on purpose: DictationRefine/dictation prompts (language data), `dev/` previews, game
  arcade captions (`G A M E  O V E R`, `HI`). Key check: every literal `I18n.tr/trN` key must
  exist in ru.json (one-off python grep in the session that added it).
- ClockPlate (record/hotspot plate on the clock): the plate's width ALWAYS counts in the bar
  width (spec: the island keeps its size while the plate leaves), so a HIDDEN plate must carry
  no text — it used to say "Hotspot" and widened the bar once translated. Label: recording =
  elapsed time, hotspot = the clock (spec: same mechanics as recording); the last label is held
  while the plate flies away.

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
- Launcher needs keyboard: Island sets `WlrLayershell.keyboardFocus: Exclusive`
  only while the launcher module is open, else `None` (OnDemand focuses only on a click:
  a hotkey from a focused text field left the search field deaf).
- Config hot-reload is DEBOUNCED (`reloadDebounce`, 150 ms in `config/Config.qml`): editors
  save in several writes; reloading on the first `fileChanged` parsed a half-written file
  ("JsonAdapter ... unterminated object") and the final write's event was lost, so the
  edit only applied on the NEXT save (user saw "it doesn't re-read the value", Oct 2026).
  Verified with a split write (half, 30 ms, rest).
- ListView view transitions (add/remove/displaced/move): a `SpringAnimation` inside them
  never gets its implicit target — moved rows KEEP their old y, removed rows stay fully
  visible forever (dump showed idx=-1 rows at appear 1). And a `displaced` transition that
  does not animate y also leaves rows at the old y. Pattern (launcher): transitions only
  `PropertyAction` row flags (+ `PauseAnimation` to hold a removed row), the row's own
  Behavior springs do the motion, moves have no transition (row FLIP). Also set
  `currentIndex: -1` when the selection is your own — ListView's default current item 0
  stuck in slot 0 over the newcomer.
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
- `components/VolumeIcon.qml` (+ `VolumeGeometry.js`, Oct 2026) = shape-built speaker
  (rect rounded left + cone trapezoid, acute corners rounded) + up to 3 arcs: `arcs` fade
  on springs and the content re-centres (speaker slides), `muted` draws a TL→BR slash
  that cuts a sharp gap (Greiner–Hormann polygon − slash quad on flattened polygons),
  `pulse()` = whole icon bump, `wave()` = speaker then arcs 1..3 staggered (arcs scale
  about their centre → push outward). Tunables `Config.data.volumeIcon`. Arc fade + pulse/wave are TIMED NumberAnimations (user decision, exception to the
  Spring-only rule); only the mute slash is a spring. Used by the OSD
  (arcs by level, pulse at 0 / push down, wave at 100% / push up) and the QS media
  volume row (left: `maxArcs: 0` + slash on mute + pulse at 0; right: 3 arcs + wave at
  100%); brightness (OSD + QS slider card) bumps its filled sun glyph at 100% via
  `components/GlyphBump.qml` (= VolumeIcon pulse curve for plain glyphs). Volume hard cap = `audio.maxVolume` (1.05): `services/Audio.qml` pulls ANY
  external overshoot (wpctl binds, apps) back to it (verified: wpctl 1.4 → 1.05). Traps hit: CurveRenderer does NOT union overlapping subpaths of one path (the
  overlap vanished); `layer.enabled` items inside `RoundedClip` (hidden layer source)
  never render; a CurveRenderer Shape toggled via `visible` never repaints after being
  shown again (arcs vanished for good once the OSD hit 0 — use transparent ink /
  opacity) — and the same for ANY ancestor's `visible` (OSD volume->mic switch blanked
  the speaker AND the sibling mic glyph; fixed with opacity in OsdModule, and
  `components/FadeBlur.qml` now hides via opacity + `enabled`, no `visible`); OSD speaker
  binds the SINK (`sinkMuted`/`sinkFill`), not the current kind's value; overlapping/abutting pieces show lines on translucent ink — hence the
  exact boolean difference. The player module has no volume row yet. Dev preview window:
  `quickshell -p dev/volume-icon/shell.qml` (all variants + looping animations; watches the
  icon files itself — `components` there is a symlink quickshell's watcher ignores).
- `components/VelocityDeform.qml` (Oct 2026) = pShell BlobRect velocity deform in pure QML:
  `transform: VelocityDeform { item: <self> }` — the item's scene-centre velocity stretches it
  along the motion / compresses across (area-preserving, cap `deform.maxStretch`, attenuated by
  size like pShell Liquid.deformSizeScale), 2×2 matrix on an under-damped spring (Euler
  sub-steps ≤ 1/240 s); FrameAnimation runs only while moving/settling (woken by x/y changes).
  Tunables `Config.data.deform` (pShell Liquid values) + `diagonal` (user, Oct 2026: 0.25 —
  the stretch fades toward 45° motion by |sin 2θ| and the skew term is scaled by it; axis
  motion unchanged; 1 = pShell). Used by the capture ColorPanel crawl
  + grow-out-of-the-live-chip on open (pShell: `growT` 0→1 on a Spring, box lerps chip rect →
  panel incl. pill→panel radius, content scaled to the width + fades in, bg opaque at once,
  close fades) and the OcrPanel glide (verified on the colour panel with temp/vmouse.py frames).
- `components/RollingText.qml` = Apple numericText-style per-character drum
  roll (only changed chars roll, slots matched from the RIGHT via Row
  RightToLeft, auto direction: value up → roll UP, down → roll DOWN (user-corrected), Spring
  per slot, tabular digits via `font.features {"tnum": 1}`). Used by the
  system card metrics. Verified Oct 2026 with a slowed spring in a scratch
  FloatingWindow (`quickshell -p <dir>/shell.qml`, components symlinked).
- A `Behavior` (Spring) whose TARGET binding reads another ANIMATED value (e.g.
  `x: cx - width / 2` while width springs) is retargeted every frame and the spring
  restarts each time → the element crawls far behind its siblings. Bind targets to
  target values only (`cx - targetBox / 2`). Hit in the QS media morph (Oct 2026).
- QML property names cannot start with an upper-case letter (`property var L` →
  "Property names cannot begin with an upper case letter", the whole Shell fails to load
  — and the user's live instance hot-reloads into that).
- Canvas `loadImage(url)` of an image ALREADY in the pixmap cache (an Image elsewhere loaded
  it) completes synchronously and NEVER emits `imageLoaded`; `getContext()` before `available`
  only warns + returns null. Ready = `available && isImageLoaded(url)`, checked after
  loadImage, on imageLoaded and on availableChanged (ColorLoupe: Tab from shot → colour left
  the sampler dead, clicks never opened the colour panel; direct `captureMode color` raced
  the backdrop load and worked).
- Canvas `shadow*` (`shadowColor`/`shadowBlur`/offsets) do NOTHING in Qt:
  the Context2D properties exist (assignments don't throw) but render no
  shadow (verified Sep 2026). Build glows from layered translucent strokes
  instead (see Arcs).

## Conventions (from flicker.md)

- One file = one responsibility; ~200 lines is the split signal.
- No hardcoded sizes/thresholds — Config/Theme only.
- Every surface that sits on the translucent (frost) backdrop gets `components/InnerShadow`
  along its rim (user rule, Oct 2026): QS cards, slider capsules, the expanded-card panel,
  rail/session/edit discs, edit chips; Notification Center tiles, plates, pills, ✕ and the
  action pills / reply field (faded in with `frost.progress`, the flow card stays plain).
  Big surfaces: `innerShadowSize` / `centerInnerShadowSize`; discs and pills:
  `size = round(height × 0.3)`; strength from `innerShadowStrength` /
  `centerInnerShadowStrength`. New surfaces of this kind get one too.
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
verified headless on a nested bus with scaled timings; card layout `NotificationCard`: avatar (sender `image`, else app
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
baseline, `dashboard.headerHeight`) + 8x3 grid (unit 100px, island 892x402 — sizes baked in after a 1.25× bump, NO per-module
scale: a global scale is planned (user, Oct 2026); island size AND radius are derived in
`modules/dashboard/DashMetrics.js` (radius = cardRadius + margins, concentric — user),
no `modules.dashboard` entry; user chose growing in width):
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
codepoints: `uvx --from fonttools` + getBestCmap(). Layout is editable
like QS (Oct 2026, user: "the same as QS — an invisible grid, drag + resize"):
the arrangement above is only the stock layout (`DashCatalog.DEFAULT_LAYOUT`);
the live one is STATE in `services/DashboardLayout.qml`
(`statePath("dashboard.json")`, one page, no tabs) on the shared QsGrid engine
(pin + push, equal cards swap, empty rows squeezed). Rows grow with the
cards: island H = `DashMetrics.islandSize(cfg, rows, editing, hidden)`, edit
mode adds a drop row + the footer (`QsEditFooter`, reused via `glyphOf`).
Allowed footprints per card in `DashCatalog.js` = only shapes the content
can draw (cards no longer declare spanCols/spanRows). `DashTile` = the card
Loader (inactive while hidden: UpdatesCard polls checkupdates) + QsCard's
edit chrome (rim, `QsResizeArc` at cardRadius, "−"); its MouseAreas are
disabled outside edit mode. Presses: the module owns them (bg MouseArea:
long press → edit, swipe up > `gestures.presentationDragThreshold` →
close, tap in edit → save + leave). A passive TapHandler for the long press
was tried: flaky next to GestureZones' exclusive grab (lost the hold in
one run, the swipe-up close in another). Edit keys `dashboard.edit`
(DashMetrics.edit() supplies defaults: config.json replaces the whole
group), haptics `haptics.dashboard`. IPC dashboardEdit / dashboardResize id
w h / dashboardMove id x y. Verified with a uinput mouse (temp/vmouse.py
pattern, 1:1 relative moves after homing to 0,0): long press, drag, arc
resize, footer add, "−", tap-out, Done, swipe-up close. Updates/Events
start hidden (footer → add); content adapts (adaptive fonts/row counts); live: clock header RU, CPU/RAM/disk rings via
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

Simplified / not implemented yet (see flicker.md for the intended behaviour):
- Frost (Oct 2026, user): per-module compositor blur only in `effects.frostModules`
  (QS + `notifications:center`), iOS 18 Control Center KNOCKOUT look fitted from the user's
  iPhone samples: backdrop = wall·0.765+38 → `Theme.frostBody` #3CA2A2A2, buttons =
  wall·0.565+12 → `Theme.frostButton` #6F1C1C1C — buttons sit on the BARE blur, so the body
  goes fully clear and the tint is a Shape (CurveRenderer, even-odd: island outline +
  holes, `components/Knockout.js`) painted only BETWEEN the buttons (antialiased holes; a
  MultiEffect mask would stair-step). `Island.frostTarget` → region up at once,
  `frostProgress` (Spring `frostSpring/Damping`) fades body→clear, tint in, button
  surfaces (`frostState.surface()`) → frostButton; on close the region stays until the body
  is opaque again. Holes come from the module (`knockouts` in island coords, LIVE bindings
  that read every moving prop — no frame timer): QS cards (cut to the viewport while
  sliding, lifted card excluded — overlapping holes cancel in even-odd), notification
  tiles + stack plates (cut at `SwipeCard.coverTop`, scroll-clipped). Slider cards are
  holed whole and repaint their fill/track gap with the tint themselves (exact
  complement inside the capsule). Across ContentSwap: holes switch at the handover, a
  second Shape fills them (1 − contentOpacity on open, 1 − ghostOpacity on close; the last
  set is held + shifted with the top-centred ghost); `Knockout.insideOutline` keeps holes
  inside the morphing rounded outline. Secondary layers (idle discs, rail disc, chips,
  pills, hover ✕) only fade alpha to `effects.frostLayerOpacity`. Independent of
  `disableCompositorBlur`. Island layer namespace `flicker-island`; niri needs a
  `layer-rule` with `background-effect { xray false }` in the niri config
  or it blurs only the wallpaper; driftwm blurs windows under layer surfaces by itself
  (verified there). Accent colours (qsFill/Blue/Green, slider icons) from the samples.
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
  The second instance stays a Minimal strip for the whole session (`Island.captureMinimal`
  blocks the startup morph / minimalIdle / fs-exit lift; released on `capture.closing` or
  end), and once stolen the backdrop FILLS the live hole with the frozen frame
  (`CaptureBackdrop.holeFilled`, springs in; fades out on close over the bar re-expanding
  live) — the region preview shows the bar exactly as the screenshot will (user, Oct 2026).
  Overlay layers: `CaptureBackdrop` (frozen grab, drawn as 3 clipped pieces around a LIVE
  hole = `Island.captureHole()` band, so the steal + second instance stay visible) →
  `CaptureDim` (cut = tool's `cutRect`) → global crosshair → mode tool (Loader) →
  `CaptureSquare` (ContentSwap icon, glyph switches at the handover). Square/crosshair are
  ONE global state (`CaptureMotion`, global logical px) shifted per screen: size/radius
  springs to `squareSize`, flight = spring-driven quadratic bezier onto cursor+
  `chaseOffset` (control = `arcLead` along the chord + `arcBend`·length on the UPPER normal, +x for a straight drop — the old corner control (target.x, from.y) lay on the chord when the cursor was below the bar → straight flight; verified by polling debugState `square` during a launch), then chase springs (seamless: chaseX follows the target
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
  sampling, loupe = ShaderEffectSource `sourceRect` (span = size/zoom px of a hidden 1:1 grab
  Image, opacity 0 — an INVISIBLE ShaderEffectSource never renders, fillItem Shape drew nothing)
  filling a CurveRenderer circle — `ShapePath.fillItem` paints the texture at its NATURAL size (span×span px from the origin, edges clamped), so it needs `fillTransform: PlanarTransform.fromScale(texel)` (without it the lens centre showed the pixel +span/2 right/down; verified in a harness with coordinate-coded pixels); the old zoom-sized Image (physW×zoom ≈ 20k px) in a clip/
  MultiEffect-masked layer rendered NOTHING, loupe looked empty (fixed Oct 2026) — under a 2px ring, HSL sliders, formats,
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
  (`birthSpring`/`birthDamping`) to their slots while fading in, along an ARC: per-axis
  stiffness, the axis with the shorter way springs harder (`× 1 + birthArc · other/(dx+dy)`),
  so it lands first and the long axis trails (verified: mid-flight frame = an arch); while the frame is moved / resized the toolbar and audio chips stay up (`RegionEditor.toolsUp`) and the same springs carry them to their new slots (no hide/re-show; verified with temp/vmouse frames mid-drag); a press OUTSIDE an existing selection is `reselect` (nothing leaves yet):
  a click morphs the frame to the new region (smart rect / whole screen; buttons glide along), a
  drag past `minSelection` = `dismissForReselect`: hasSelection off (crosshair + bubble return),
  the old frame FLOWS into the one being drawn and the toolbar / chips retract into the live
  bubble (reverse birth, fade `squareHideDelayMs`), new ones are born on release. Frame motion =
  FLIP: drawn rect `view*` = sel + `off*` (set to old − new, spring to 0 on `capture.frameSpring/
  frameDamping`), so live drags stay exact; frame, dim cut, handles, size badge draw `view*`,
  layout + hit tests read `sel*`. A fresh click selection grows out of the press point the same
  way. Verified with vmouse + grim frames; the bubble lingers
  `squareHideDelayMs` before fading so they visibly leave it. Tools are below the bubble
  in z (overlay order), that is what hides them at birth.
  Recording: `services/Recorder` runs `scripts/capture/record.sh` (pShell port): audio
  none|system|mic|both (both = two parecords — sink monitor + mic — amixed by ffmpeg per segment; the
  old null-sink + 2 loopbacks mix recorded DIGITAL SILENCE in ~1 of 4 runs when another stream
  started meanwhile, graph linked fine — reproduced with pw-play, Oct 2026), pause = segment split (SIGUSR1), live
  audio switch (`.audioctl` + SIGUSR2), discard, VAAPI via `recorder.hwDevice`.
  wf-recorder 0.6 drops the video with `--audio` (pulse) and the audio with
  `--audio-backend=pipewire` — so record.sh captures video (wf-recorder) and audio
  (`parecord --latency-msec=50`; default latency loses ~2s of buffer on SIGINT)
  separately and muxes per segment (`-c:v copy -af apad -shortest`, silent track for
  "none" so concat stays compatible). Region = `-o <output> -F crop=w:h:x:y` (physical px, even
  w/h), NOT `-g`: driftwm 0.19 screencopy ignores the region offset (always the top-left
  corner, verified Oct 2026; IPC `Compositor.startRecording(region)` still uses `-g`). All its PipeWire nodes are `flicker_rec*` →
  ignored by the mic indicator. Island controls: `RecordingActionsModule` (dot, h:mm:ss, speed drum
  `SpeedRuler` → `Recorder.speed` (`recorder.speeds`/`ruler`), discard,
  audio cycle, pause, stop; layout copied from the user's iOS reference shot, scaled 96/182 —
  gaps in `recorder.controls`, island width = module `preferredWidth`; at rest only pause + stop and
  the ruler is centred, hovering the buttons (root HoverHandler, zone measured from the RIGHT edge
  by the live `reveal` — from the left it flapped as the centred island grew) widens the island and
  discard + audio fade/scale in, anchored to the live width; `hoverHoldMs` before closing). No
  auto-open on opening: armed only after the rest width and positive evidence (pointer off the zone
  `armDelayMs`, left the island, or entered within `entryEdge` of an edge; enter events can carry a
  stale scene 0,0 → points outside the module are skipped). Pointer x from the WINDOW position
  (`point.position` is stale while the island grows under a still pointer). Logic verified with a
  scripted harness overriding `pointerIn/pointerSceneX/Y` — uinput pointer tests on driftwm were
  unreliable (pushing the cursor into a screen edge stops the hover events). on the red plate click / IPC recordControls.
  uv scripts (`regions.py` opencv smart regions, niri `nudge.py`) run via
  `CaptureActions.uvScript()` = `uv run --offline ... || uv run ...`: online `uv run
  --script` re-resolved deps on every start (~55s vs 1.6s offline).
  Verified on driftwm (IPC + debugState + screenshots): grab→steal→flight→chase, frozen
  backdrop + live hole, dim math (×0.65), shot commit 3/3 (PNG from the frozen grab, no
  overlay), AI → OCR panel, record → audio chips → recording (h264+aac, pause/stop via
  IPC), window highlight → editor preset, pipette loupe, recording controls render,
  record.sh modes none/system(+pause+switch to mic)/both standalone.
  Speed (Oct 2026): a ruler change (debounced `recorder.speedApplyMs`) writes `<file>.speedctl` +
  SIGUSR2 = new segment from that moment; each finished segment is muxed + re-timed (setpts +
  atempo chain, libx264, `-fps_mode vfr -enc_time_base 1/maxFps` — ffmpeg 9 rejects -r/-fpsmax
  with vfr) by a niced BACKGROUND finisher while the next segment already records (waiting for
  wf-recorder to exit left multi-second capture gaps); any speed used → final concat through the
  concat FILTER (the demuxer mis-timed mixed time bases: video 2.7 s vs audio 5.8 s). Audio
  modules are kept across segments of the same source. `Recorder.recording` drops at stop, the
  file is assembled in the background (`saving`; start refused meanwhile); region marker =
  `modules/capture/RecordRegionOverlay` (per screen, Top layer, empty mask): dim outside +
  frame `frameGap` outside `Recorder.regionCrop` (exact even-rounded phys crop, logical rect
  rounded OUTWARD) — never inside the video; `recorder.region` tunables. It maps when the
  capture overlay STARTS fading (`Recorder.prepareRegion` → `regionPending`, guard
  `pendingMaxMs`) in the editor's selection-frame look, then one spring `k` morphs it (user:
  the same frame, only recoloured): colour → `recordFrame`, width, dash gap 0 → `dashGap`
  (CurveRenderer `DashLine` verified in a harness), radius. Hand-over = `CaptureScope.handover`:
  the WHOLE capture overlay incl. the frozen backdrop fades with dimLevel (the marker below
  crossfades in) — an opaque backdrop that only lost its dim and then unmapped = dim + frame
  blink (user); `regionPending` drops only AFTER `recording` (else the marker re-showed); discard = `<file>.discard`
  flag → no re-time / assembly. TEST TRAP: wf-recorder only writes frames on DAMAGE — on a still
  screen a segment gets no frames (no file) and SIGINT waits for the next frame (12 s seen); run
  an animated overlay while testing. Verified standalone (all speeds 0.25–4×: durations exact, A/V
  ≤0.07 s) and through the Recorder service; NOT tested from the live island. NOT live-tested (no
  mouse/keyboard tool): drawing tools, text annotations, palette, toolbar clicks, resize
  handles, colour panel editing, OCR language chips, Lens upload, Esc chain, multi-monitor.
  Selections are per screen (pShell parity); only aim visuals span monitors.
  Code scan (Oct 2026): mode `scan` (shares the RegionEditor with shot/record/ai) + a QR
  button in the toolbar → `editor/ScanPanel` (+ `ScanRow`): `zbarimg -q --xml
  -Stest-inverted` on the pure grab crop (inverted = dark-mode codes), outlines over the found
  codes (polygon from the XML, crop px / dpr), rows copy on click, http/mailto get "open"
  (xdg-open + done); one result is copied silently, Enter copies all + closes. OCR and scan
  panels are mutually exclusive and share `RegionEditor.panelPlace()`. Verified via IPC:
  panel renders, toolbar button checked, empty result; parser on real zbar XML. NOT
  live-tested with a code on screen.
  Buttons (Oct 2026, user): capture IconButtons (`tile: true`) and the audio chips use the
  wallpaper-settings icon-tile look = `components/IconTile` (Theme `wallSettingsIcon*` gradient +
  `CardRim`, radius `capture.toolRadius`, hover veil `Theme.iconTileHover`, checked / `tileFill`
  = lighter→darker of that colour, glyph CurveRendering at the exact centre); the audio bar's
  radius is concentric (toolRadius + toolSpacing). Verified on a grim frame (record chips). The cursor bubble
  (`CaptureSquare`) leaves as the island (black + island rim) and fades into the same IconTile while
  it flies (`tileLevel` = motion.flight, 1 while chasing); `CardRim`/`IconTile` take a separate
  `topLeftRadius` for its tip corner. Chase point clamped `chaseEdgeMargin` inside the cursor's
  screen (right / bottom, pShell CursorGuide; screen found in `Quickshell.screens` by pointerAt).
  Non-tile IconButtons (stash) keep the GlowRim below:
  `components/IconButton` carries a barely-visible white glow
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
- (DONE Oct 2026) Stash = pShell file tray + LocalSend port. Services `services/Stash.qml`
  (tray dir model, diff-updated; drop copy|symlink; shell ops queued) and
  `services/LocalSend.qml` (outbound discover→pick→send, phase idle|scanning|ready|sending;
  inbound receive server, session toggle `receiving`, default `stash.receive`) — scripts
  in `scripts/localsend/` (stdlib python3, run directly). Modules: `stash` (payload.view
  tray|send|incoming; every view change = `openModule` via ModuleHost `openRequested`, so
  the swap replays; `returnView: "tray"` = go back to the tray when done) — opened by
  IPC `island stash` (toggle), the QS `localsend` card (`services.openStash`) or an incoming LocalSend request; `stash-drop` = the pShell
  drop chooser (tray tile: dashed outline on hover; LocalSend tile: tinted) — opened by a
  file drag over the island: `Island.islandDrop` (DropArea BELOW the content, covers the
  island + the band above it + the Minimal zone; mask gets that band while the chooser is
  open) + `ModuleHost.dragActive` (the chooser's tile DropAreas steal containsDrag) →
  `stashDropLeave` closes after `stash.dropLeaveMs`. Own tile drag-outs set
  `Stash.outgoingDrag` (ignored as a drop, keeps the tray/moduleIdle alive; Drag.active is
  set imperatively — binding it segfaulted pShell). Island sizes: `StashMetrics.js`.
  Tile actions (user, Oct 2026): hover shows ONE "⋯" button (top-right); a click grows it
  through the tray's `DropExpand` into `StashTileMenu` (file name + glyph discs with labels:
  Open (xdg-open), Send (LocalSend), Pin/Unpin (fav), Transcript (audio/video), Delete); every
  action runs via `expander.close(fn)` after the drop is back. Sizes `stash.menu`. Debug IPC
  `island stashMenu <i>` (-1 folds). Verified via IPC + grim frames; mouse NOT tested.
  Types: `modules/stash/StashTypes.js` = ONE kind table (tile icon/thumb, menu actions via
  `actions(tile, tr)` — tray menu width/rows are derived from it, wrap to rows past the tray width;
  scanner `ls -1Ap` → `isDir`). Multi-select (Oct 2026, user): `Stash.selection` {path: true}
  (pruned on rescan), Ctrl+click toggle, Shift+click range from `anchorPath`, plain click toggles
  while selecting, rubber band = MouseArea BELOW the tiles on empty grid space (a click there
  clears; swipe-up close must start outside the grid while files are shown); dragging a SELECTED
  tile drags every selected uri; the action row crossfades into the group bar (send · compress ·
  delete | "n selected" | select all · clear). Archives: `scripts/stash/archive.sh` pack (zip -r -y,
  unique "x 2.zip") / unpack (bsdtar, 7z fallback; one top entry lands as itself, several in
  "<stem>/", bare .gz/.xz/.bz2/.zst just decompressed; temp `.unpack.*` hidden from the scanner);
  failure = notify-send. Quick Look = stash view "preview" (`StashPreview` + `StashPreviewMedia`
  (MediaPlayer with sound, looped; click / P pause, seek strip) + `StashPreviewText` (text head,
  folder / archive listing, `file -b` + size)); island fitted via `Stash.preview` {kind, w, h} —
  a BINDING from the body's naturalW/H (a cached image is Ready before onCompleted, a write there
  zeroed it); the body Loader is re-activated on every path change (a same-kind step reused the
  body and showed the previous file). Keyboard: Exclusive while tray / preview shows
  (`StashModule.wantsKeyboard`): tray Space = preview hovered / first selected, Ctrl+A, Delete,
  Esc clears selection then closes; preview Space/Esc back, ←/→ step (wraps), Enter = xdg-open.
  Double click a tile = preview. IPC `island stashPreview <path>`. Verified via IPC + wtype + grim:
  image / video / text / zip previews and their island fits (709×520, 668×426), Ctrl+A group bar,
  menus (zip: Extract, audio: 8 actions in one row), archive.sh on scratch files. NOT tested:
  mouse (clicks, Ctrl/Shift, rubber band, group drag-out, seek strip), compress/extract from the UI,
  audio preview, PDF preview.
  Verified via IPC + screenshots: tray (image/PDF thumbs), chooser, picker scanning → none
  found, cancel-on-close. NOT live-tested: real drags in/out, device rows, sending,
  incoming card. pShell's receive server uses the same port 53317 — never both on.
  Process gotcha (hit here): `running = false; running = true` in one tick does NOT
  restart a live Process and the killed run still delivers its partial stdout — queue
  the restart in `onExited` and skip that one output (`LocalSend.rescanQueued/scanKilled`,
  `Stash.rescanQueued`). The receive server dying (port busy) flips `receiving` off.
- Player backdrop: blurred album art fills the module (MediaCard pattern,
  `RoundedImage.blur` rounded to `island.radius` via `surfaceRadius` — island clip is
  rectangular) + horizontal dark scrim; controls use translucent white on top.
  Track change: backdrop and cover are `components/CrossfadeImage.qml` (two layers,
  one Spring driver; cover pops 0.85→1 over the old one shrinking, backdrop fades
  in over an opaque old frame — `exitFade: false`, no scale >1 on clipped surfaces).
- Dictation layout-switch mode `dual` (hot ru+en sessions, zero-latency routing
  on layout switch) is PLANNED, not implemented: `config.dictation.switchMode`
  reserves the key, anything but `"restart"` warns and behaves as `"restart"`.
  Rationale: nemo-speech rejects `session.update` once audio started, so the
  language is per-session; dual needs a mic tee + per-stream routing.
