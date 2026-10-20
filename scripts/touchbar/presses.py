#!/usr/bin/env python3
"""Touch Bar presses for services/TouchBar.qml (Macs with tiny-dfr only).

Reads the key events tiny-dfr emits on its own uinput device ("Dynamic
Function Row Virtual Input Device") — only Touch Bar buttons, never the main
keyboard — and maps each key back to the button that sent it, laid out the
way tiny-dfr draws it (src/main.rs FunctionLayer::draw: equal virtual
buttons, 16 px gaps, Stretch, an "esc" button prepended when the bar is
>= 2170 px, the pixel-shift margin). stdout, one line per change:

    down <id> <x> <w>    id = "<layer>:<index>", x = centre, w = width,
                         both fractions of the bar length (0..1)
    up <id>
    reset                device lost: everything is released

Key codes never leave this process. The config (/etc/tiny-dfr/config.toml
over /usr/share/tiny-dfr/config.toml) is re-read when its mtime changes, so a
layout switch (dfr-switcher cp) is picked up on the next press. The device
is never grabbed: the compositor still gets every key.

Access: scripts/touchbar/udev.rules (uaccess). Without it, or without
tiny-dfr running, the script waits and re-checks every RESCAN_S seconds
(the hint is logged once to stderr).
"""
import errno, glob, os, re, select, struct, sys, time, tomllib

DEVICE_NAME = "Dynamic Function Row Virtual Input Device"
BASE_CFG = "/usr/share/tiny-dfr/config.toml"
USER_CFG = "/etc/tiny-dfr/config.toml"
CODES_H = "/usr/include/linux/input-event-codes.h"
BUTTON_SPACING_PX = 16
PIXEL_SHIFT_WIDTH_PX = 22
ESC_MIN_WIDTH = 2170
DEFAULT_WIDTH = 2008
RESCAN_S = 5
EV_KEY = 1
EVENT = struct.Struct("llHHi")

# input-linux Key names (tiny-dfr Action) whose KEY_ constant differs by more
# than case and underscores.
ALIASES = {f"num{i}": f"{i}" for i in range(10)}
ALIASES.update({
    "illumtoggle": "kbdillumtoggle", "illumdown": "kbdillumdown", "illumup": "kbdillumup",
    "hangul": "hangeul", "nonusbackslashandpipe": "102nd", "audio3dmode": "3dmode",
    "tenchannelsup": "10channelsup", "tenchannelsdown": "10channelsdown",
})


def log(msg):
    print(f"[TouchBar] {msg}", file=sys.stderr, flush=True)


def norm(name):
    return name.replace("_", "").lower()


def key_codes():
    codes = {}
    with open(CODES_H) as f:
        for m in re.finditer(r"^#define\s+KEY_(\w+)\s+(0x[0-9a-fA-F]+|\d+)", f.read(), re.M):
            codes.setdefault(norm(m.group(1)), int(m.group(2), 0))
    return codes


def bar_width():
    # appletbdrm connector, mode "60x2008" (portrait): tiny-dfr's width is
    # the long side.
    for c in glob.glob("/sys/class/drm/card*-USB-*"):
        try:
            if open(f"{c}/status").read().strip() != "connected":
                continue
            mode = open(f"{c}/modes").readline().strip()
            return max(int(v) for v in mode.split("x"))
        except (OSError, ValueError):
            continue
    return DEFAULT_WIDTH


class Layout:
    def __init__(self):
        self.mtime = None
        self.buttons = {}  # code -> [(id, x, w, exact)]
        self.codes = key_codes()

    def stale(self):
        try:
            m = os.stat(USER_CFG).st_mtime_ns
        except OSError:
            m = 0
        return m != self.mtime

    def load(self):
        try:
            self.mtime = os.stat(USER_CFG).st_mtime_ns
        except OSError:
            self.mtime = 0
        with open(BASE_CFG, "rb") as f:
            cfg = tomllib.load(f)
        try:
            with open(USER_CFG, "rb") as f:
                cfg.update(tomllib.load(f))
        except (OSError, tomllib.TOMLDecodeError) as e:
            log(f"{USER_CFG}: {e}, using the defaults")
        width = bar_width()
        shift = PIXEL_SHIFT_WIDTH_PX if cfg.get("EnablePixelShift") else 0
        media, fkeys = cfg.get("MediaLayerKeys", []), cfg.get("PrimaryLayerKeys", [])
        if width >= ESC_MIN_WIDTH:
            esc = {"Text": "esc", "Action": "Esc"}
            media, fkeys = [esc] + media, [esc] + fkeys
        layers = [media, fkeys] if cfg.get("MediaLayerDefault") else [fkeys, media]
        self.buttons = {}
        # Default layer first: a key on both layers lands on the visible one.
        for li, keys in enumerate(layers):
            self.add_layer(li, keys, width, shift)

    def add_layer(self, li, keys, width, shift):
        stretches = [max(1, int(k.get("Stretch", 1))) for k in keys]
        count = sum(stretches)
        if count == 0:
            return
        vw = (width - shift - BUTTON_SPACING_PX * (count - 1)) / count
        start = 0
        for bi, (k, s) in enumerate(zip(keys, stretches)):
            left = int(start * (vw + BUTTON_SPACING_PX)) + shift / 2
            bw = vw + int((s - 1) * (vw + BUTTON_SPACING_PX))
            start += s
            action = k.get("Action", [])
            action = [action] if isinstance(action, str) else action
            # No label = an empty slot, tiny-dfr ignores its action.
            if not action or not any(k.get(f) for f in ("Text", "Icon", "Svg", "Time", "Battery")):
                continue
            for name in action:
                code = self.codes.get(ALIASES.get(norm(name), norm(name)))
                if code is None:
                    log(f"unknown key {name!r}")
                    continue
                self.buttons.setdefault(code, []).append(
                    (f"{li}:{bi}", (left + bw / 2) / width, bw / width, len(action) == 1))

    def find(self, code):
        if self.stale():
            self.load()
        hits = self.buttons.get(code)
        if not hits:
            return None
        # A button sending just this key beats a combo that contains it
        # (LeftCtrl of a Ctrl+C button).
        return next((h for h in hits if h[3]), hits[0])


def find_device():
    for p in glob.glob("/sys/class/input/event*/device/name"):
        try:
            if open(p).read().strip() == DEVICE_NAME:
                return "/dev/input/" + p.split("/")[4]
        except OSError:
            continue
    return None


def out(line):
    sys.stdout.write(line + "\n")
    sys.stdout.flush()


def run(dev, layout):
    fd = os.open(dev, os.O_RDONLY)
    log(f"reading {dev}")
    held = {}  # id -> set of codes down
    try:
        while True:
            select.select([fd], [], [])
            data = os.read(fd, EVENT.size * 64)
            for off in range(0, len(data) - EVENT.size + 1, EVENT.size):
                _, _, typ, code, value = EVENT.unpack_from(data, off)
                if typ != EV_KEY or value == 2:
                    continue
                hit = layout.find(code)
                if hit is None:
                    continue
                bid, x, w, _ = hit
                codes = held.setdefault(bid, set())
                if value == 1:
                    if not codes:
                        out(f"down {bid} {x:.5f} {w:.5f}")
                    codes.add(code)
                elif code in codes:
                    codes.discard(code)
                    if not codes:
                        out(f"up {bid}")
    finally:
        os.close(fd)
        if any(held.values()):
            out("reset")


def main():
    layout = Layout()
    layout.load()
    hinted = None
    while True:
        dev = find_device()
        if dev is None:
            if hinted != "nodev":
                log("no tiny-dfr device (tiny-dfr not running?), waiting")
                hinted = "nodev"
            time.sleep(RESCAN_S)
            continue
        try:
            run(dev, layout)
        except PermissionError:
            if hinted != "access":
                here = os.path.dirname(os.path.abspath(__file__))
                log(f"no access to {dev} — install the udev rule:\n"
                    f"  sudo install -m644 {here}/udev.rules /etc/udev/rules.d/70-flicker-touchbar.rules\n"
                    f"  sudo udevadm control --reload && sudo udevadm trigger -s input")
                hinted = "access"
            time.sleep(RESCAN_S)
        except OSError as e:
            # ENODEV: tiny-dfr restarted, its device is recreated.
            if e.errno not in (errno.ENODEV, errno.ENOENT):
                raise
            log("device gone, waiting for it")
            hinted = None
            time.sleep(1)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
