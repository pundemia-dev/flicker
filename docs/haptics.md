# Trackpad haptics

Flicker can tick the trackpad (Force Touch / haptic touchpads) on a few
moments. The shell itself knows nothing about hardware: it sends abstract
effects to a **backend** — a small long-running program that makes the
device vibrate. Pick a bundled backend, or write your own in any language.

## When it ticks

| Moment | Effect | Config toggle |
|---|---|---|
| Volume / brightness changed by a key bind, at every 10 % mark (reached or passed, either direction) | `tick` | `haptics.osdSteps`, `haptics.osdStepEvery` |
| Quick Settings: long press → edit mode | `deep` | `haptics.quickSettings` |
| Quick Settings: a dragged card snaps to a new layout | `click` | `haptics.quickSettings` |
| Quick Settings: tab switch; a resized card snaps to a new size | `release` | `haptics.quickSettings` |
| QS volume/brightness slider reaches 0 or 100 %; seek bar dragged past an end | `release` | `haptics.limits` |
| Wallpaper carousel: a card passes the centre (keys, wheel, click; a far jump = one click) | `click` | `haptics.wallpapers` |

Quick Settings slider moves themselves do not tick. Haptics are felt only
under a finger on the trackpad — on key presses you mostly *hear* the tick.

## Setup

1. Check what the shell found — the log line starts with `[haptics]`:
   - `backend <name> (<device>)` — working, nothing to do;
   - `<name>: ... not writable — install .../udev.rules` — hardware found, the
     device needs a permission rule (step 2);
   - `no haptic hardware found` — no supported device: haptics stay off
     silently (or write a backend, below).
2. Install the udev rule of that backend (needs root once):
   ```sh
   sudo install -m644 scripts/haptics/backends/<name>/udev.rules \
        /etc/udev/rules.d/70-flicker-<name>.rules
   sudo udevadm control --reload
   sudo udevadm trigger            # re-applies rules to devices already plugged in
   ```
   The rules use `TAG+="uaccess"`: the user logged in at the seat gets an ACL
   on that one device, nothing world-writable. The shell probes again every
   `haptics.rescanMs` (30 s) while no backend is usable, so it picks the device
   up by itself — no restart needed.

## Bundled backends

| Name | Hardware | How |
|---|---|---|
| `evdev-haptic` | Any haptic touchpad driven by the **kernel** (Linux 6.18+ HID haptics: Elan and other haptic pads; Apple trackpads once their driver is merged) | evdev force feedback, effect type `FF_HAPTIC` (HID waveforms CLICK / PRESS / RELEASE). Never uses `FF_RUMBLE` (gamepads). *Not yet tested on hardware.* |
| `apple-t2` | Intel MacBooks with the T2 chip (2018–2020), Force Touch trackpad | Raw HID: output report `0x53` on interface 3 of the internal keyboard/trackpad. Verified on `05ac:0340`. `release` is the driver's segment-less release packet; `tick` plays the click waveform. |

`backend: "auto"` tries them in `haptics.order` (kernel path first) and uses
the first usable one.

## Config (`config/config.json` → `haptics`)

```jsonc
"haptics": {
  "enabled": true,
  "backend": "auto",                    // "auto" | a bundled name | a path
  "order": ["evdev-haptic", "apple-t2"],// auto mode probe order
  "minIntervalMs": 40,                  // rate limit (held keys, drags)
  "respawnMs": 5000,                    // restart delay after a backend crash
  "rescanMs": 30000,                    // re-probe while nothing is usable (0 = never)
  "osdSteps": true, "quickSettings": true, "limits": true, "wallpapers": true,
  "intensity": { "click": 1, "deep": 1, "release": 1, "tick": 1 }, // 0..1, 0 = off
  "backendOptions": {                   // passed to the backend as JSON
    "apple-t2": { "click": { "strength": 40, "softness": 144 } }
  }
}
```

## Writing a backend

Copy `scripts/haptics/backends/_template/` to a new directory (in the repo, or
anywhere and point `haptics.backend` at it), make `backend` executable, fill
in the TODOs. A backend is one executable with two commands:

### `backend probe`

Exit code tells the shell whether to use it:

| Exit | Meaning | Print |
|---|---|---|
| `0` | usable | the device (shown in the log) |
| `1` | no such hardware | nothing |
| `2` | hardware present, no access | a hint: which udev rule / group is missing |

Must be fast (5 s timeout) and must **not** touch the hardware beyond reading
sysfs / checking permissions.

### `backend run --options '<json>'`

Long-lived. Reads lines from stdin until it closes:

```
<effect> <intensity>
```

- `effect`: `click` (short, crisp — a threshold or a snap), `deep` (strong,
  heavier — a mode change), `release` (light — hitting a limit), `tick`
  (lightest detent — passing a value mark). Unknown effects: ignore (more may
  be added).
- `intensity`: `0..1`; `1` = your device's normal full-strength version of the
  effect, `0` = play nothing. Map it to your hardware's scale.
- `--options`: `haptics.backendOptions.<your directory name>` as JSON (`{}` if
  unset) — device path overrides, tuning tables.

Rules:

- **Never crash** on bad input or a disappearing device: log to stderr
  (it lands in the shell log), back off, reopen later. If the process exits
  anyway, the shell restarts it after `respawnMs`.
- **Only send what you know the device accepts.** Vendor protocols are often
  undocumented; guessed bytes can wedge or reset hardware (the T2 actuator
  resets the whole keyboard/trackpad for ~5 s on a rejected packet). Get
  packets from a driver or from a capture, not by trial and error on a live
  device.
- **One writer at a time.** Two processes driving the same device can race
  (on the T2, two overlapping control transfers stall the bus). Take an
  exclusive `flock` on the device and stay silent when it is held — a second
  shell instance must not double-drive the hardware.
- Don't rate-limit or decide *when* to vibrate — the shell does that.
- Stay idle-cheap: block on stdin, no polling.

### Testing a backend by hand

```sh
scripts/haptics/backends/<name>/backend probe; echo "exit $?"
printf 'click 1\n' | scripts/haptics/backends/<name>/backend run --options '{}'
# the whole chain, as the shell runs it:
printf 'click 1\ndeep 1\n' | python3 scripts/haptics/run.py --backend <name>
```

Tip: point a hidraw-style backend's device option at a plain file to see the
exact bytes it would send (`xxd` it) before touching real hardware.
