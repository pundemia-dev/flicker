#!/usr/bin/env python3
"""Night Light gamma helper: a bare Wayland client for wlr-gamma-control.

No wlsunset / gammastep / pywayland: the wire protocol is spoken directly
over the compositor socket (niri, driftwm, Hyprland, sway all serve
zwlr_gamma_control_manager_v1). services/NightLight.qml owns the schedule;
this process only paints colour temperatures and animates between them.

Reloads must not touch the screen: a control dies with its Wayland
connection (= identity, a cold flash) and the compositor refuses a second
one for the same output while the old is still held. So the first run
forks a DAEMON that owns the connection, listening on the abstract socket
"flicker-gammad-$WAYLAND_DISPLAY"; every run (one per shell generation) is
a thin relay between its stdin / stdout and that socket. A new shell
generation reconnects to the same daemon and sends the same targets —
nothing changes on screen. With no client for LINGER_S the daemon exits
(the shell really quit) and the colours return. A daemon started from an
older gammad.py (mtime) is told to quit and replaced.

stdin, one JSON object per line:
  {"temps": {"*": 4000, "DP-1": 6500}, "fade": 900}
      target K per output ("*" = every output not named), eased over
      `fade` ms in mired space (perceptually even; a kelvin lerp rushes
      the warm end)
  {"reapply": true}     resend every ramp (after a resume from suspend)
stdout, one line per event:
  ready                 the gamma manager is there
  unsupported           the compositor has no wlr-gamma-control
  outputs <name,...>    controllable outputs changed
  failed <name>         the compositor refused / dropped the control
                        (another gamma client holds the output)

An output at 6500 K (neutral) with no fade running releases its control:
the compositor puts back its own identity ramp, nothing stays applied.
Relay exit: 0 stdin EOF, 3 unsupported, 1 daemon gone.
"""
import array
import json
import math
import os
import selectors
import socket
import struct
import sys
import time

NEUTRAL = 6500
# Fade upload rate. Each set_gamma = a blocking DRM commit in the
# compositor: 15-31 ms (1-2 vblanks) measured on driftwm 0.19 / i915,
# ~26 ms on niri (noctalia) — faster fades would drop its frames.
FRAME_S = 1 / 15
LINGER_S = 3.0
SOCK = "\0flicker-gammad-" + os.path.basename(os.environ.get("WAYLAND_DISPLAY", "wayland-0"))
STAMP = str(os.stat(os.path.abspath(__file__)).st_mtime_ns)
# Refused controls (another gamma client): retried after 0.25 s, doubling.
RETRIES = 6

CLIENTS = []  # daemon: connected relays


def log(*a):
    print("[gammad]", *a, file=sys.stderr, flush=True)


def emit(line):
    data = (line + "\n").encode()
    for c in CLIENTS[:]:
        try:
            c.sendall(data)
        except OSError:
            CLIENTS.remove(c)


# --- colour --------------------------------------------------------------
# White point of a colour temperature, wlsunset's model (also DMS): CIE
# daylight illuminant D above 4000 K, the Planckian locus below 2500 K, a
# cosine blend between; XYZ → linear sRGB, normalised to the brightest
# channel (white stays as bright as the panel allows).

def _illuminant_d(t):
    if t <= 7000:
        x = 0.244063 + 0.09911e3 / t + 2.9678e6 / t**2 - 4.6070e9 / t**3
    else:
        x = 0.237040 + 0.24748e3 / t + 1.9018e6 / t**2 - 2.0064e9 / t**3
    return x, -3 * x * x + 2.870 * x - 0.275


def _planckian(t):
    if t <= 4000:
        x = -0.2661239e9 / t**3 - 0.2343589e6 / t**2 + 0.8776956e3 / t + 0.179910
        if t <= 2222:
            y = -1.1064814 * x**3 - 1.34811020 * x**2 + 2.18555832 * x - 0.20219683
        else:
            y = -0.9549476 * x**3 - 1.37418593 * x**2 + 2.09137015 * x - 0.16748867
    else:
        x = -3.0258469e9 / t**3 + 2.1070379e6 / t**2 + 0.2226347e3 / t + 0.240390
        y = 3.0817580 * x**3 - 5.87338670 * x**2 + 3.75112997 * x - 0.37001483
    return x, y


def _srgb(v):
    v = min(1.0, max(0.0, v))
    return 12.92 * v if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055


def whitepoint(t):
    t = max(1667, min(25000, int(t)))
    if t == NEUTRAL:
        return 1.0, 1.0, 1.0
    if t >= 4000:
        x, y = _illuminant_d(t)
    elif t >= 2500:
        x1, y1 = _illuminant_d(t)
        x2, y2 = _planckian(t)
        f = (math.cos(math.pi * (4000 - t) / 1500) + 1) / 2
        x, y = x1 * f + x2 * (1 - f), y1 * f + y2 * (1 - f)
    else:
        x, y = _planckian(t)
    z = 1 - x - y
    r = _srgb(3.2404542 * x - 1.5371385 * y - 0.4985314 * z)
    g = _srgb(-0.9692660 * x + 1.8760108 * y + 0.0415560 * z)
    b = _srgb(0.0556434 * x - 0.2040259 * y + 1.0572252 * z)
    m = max(r, g, b) or 1
    return r / m, g / m, b / m


def ramp(size, t):
    wp = whitepoint(t)
    out = array.array("H", bytes(6 * size))
    top = size - 1 or 1
    for c in range(3):
        k = wp[c] * 65535 / top
        base = c * size
        for i in range(size):
            out[base + i] = int(i * k)
    return out.tobytes()


def mix_kelvin(a, b, p):
    """a → b at p (0..1) in mireds."""
    ma, mb = 1e6 / a, 1e6 / b
    return 1e6 / (ma + (mb - ma) * p)


def ease(p):
    return p * p * (3 - 2 * p)


# --- Wayland wire --------------------------------------------------------

class Wire:
    def __init__(self):
        name = os.environ.get("WAYLAND_DISPLAY", "wayland-0")
        path = name if name.startswith("/") else os.path.join(os.environ["XDG_RUNTIME_DIR"], name)
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(path)
        self.sock.setblocking(False)
        self.next_id = 2  # 1 = wl_display
        self.buf = b""
        self.handlers = {}  # object id → fn(opcode, payload)

    def new_id(self, handler):
        oid = self.next_id
        self.next_id += 1
        self.handlers[oid] = handler
        return oid

    def send(self, oid, opcode, payload=b"", fd=None):
        msg = struct.pack("=II", oid, ((8 + len(payload)) << 16) | opcode) + payload
        anc = [(socket.SOL_SOCKET, socket.SCM_RIGHTS, struct.pack("=i", fd))] if fd is not None else []
        self.sock.setblocking(True)
        try:
            self.sock.sendmsg([msg], anc)
        finally:
            self.sock.setblocking(False)

    def read(self):
        try:
            data = self.sock.recv(65536)
        except BlockingIOError:
            return True
        if not data:
            return False
        self.buf += data
        while len(self.buf) >= 8:
            oid, word = struct.unpack_from("=II", self.buf)
            size = word >> 16
            if len(self.buf) < size:
                break
            payload, self.buf = self.buf[8:size], self.buf[size:]
            h = self.handlers.get(oid)
            if h:
                h(word & 0xFFFF, payload)
        return True


def wl_string(s):
    b = s.encode() + b"\0"
    return struct.pack("=I", len(b)) + b + b"\0" * (-len(b) % 4)


def read_string(payload, off):
    n = struct.unpack_from("=I", payload, off)[0]
    s = payload[off + 4: off + 4 + n - 1].decode(errors="replace")
    return s, off + 4 + n + (-n % 4)


# --- outputs -------------------------------------------------------------

class Output:
    def __init__(self, gd, global_name, oid):
        self.gd = gd
        self.global_name = global_name
        self.oid = oid
        self.name = ""
        self.ctrl = 0
        self.size = 0
        self.failed = False
        self.fail_count = 0
        self.retry_at = 0.0
        self.shown = NEUTRAL      # K currently on screen (last upload)
        self.fade_from = NEUTRAL
        self.target = NEUTRAL
        self.fade_t0 = 0.0
        self.fade_ms = 0.0
        self.sent = None          # rounded K of the last upload

    def on_event(self, opcode, payload):
        if opcode == 4:  # name (v4)
            self.name, _ = read_string(payload, 0)
        elif opcode == 2:  # done
            self.gd.outputs_changed()

    def on_ctrl(self, opcode, payload):
        if opcode == 0:  # gamma_size
            self.size = struct.unpack_from("=I", payload)[0]
            self.fail_count = 0
            self.sent = None
            self.gd.dirty = True
        elif opcode == 1:  # failed
            log("control failed:", self.name)
            emit(f"failed {self.name}")
            self.gd.wire.send(self.ctrl, 1)  # destroy
            self.ctrl = 0
            self.size = 0
            self.failed = True
            self.retry_at = time.monotonic() + 0.25 * 2 ** self.fail_count
            self.fail_count += 1
            self.gd.dirty = True

    def current(self, now):
        if self.fade_ms <= 0:
            return self.target
        p = (now - self.fade_t0) * 1000 / self.fade_ms
        if p >= 1:
            self.fade_ms = 0
            return self.target
        return mix_kelvin(self.fade_from, self.target, ease(max(0.0, p)))

    def retarget(self, k, fade_ms, now):
        if k == self.target:
            return
        self.fade_from = self.current(now)
        self.target = k
        self.fade_t0 = now
        self.fade_ms = fade_ms if abs(1e6 / self.fade_from - 1e6 / k) > 2 else 0

    @property
    def fading(self):
        return self.fade_ms > 0


class Gammad:
    def __init__(self):
        self.wire = Wire()
        self.manager = 0
        self.manager_seen = False
        self.outputs = {}  # global name → Output
        self.temps = {"*": NEUTRAL}
        self.fade = 0
        self.dirty = True
        self.last_names = None
        self.status = ""
        self.registry = self.wire.new_id(self.on_registry)
        self.wire.handlers[1] = self.on_display
        self.wire.send(1, 1, struct.pack("=I", self.registry))  # get_registry
        self.sync_id = self.wire.new_id(self.on_initial_sync)
        self.wire.send(1, 0, struct.pack("=I", self.sync_id))   # sync

    def on_display(self, opcode, payload):
        if opcode == 0:  # error
            oid, code = struct.unpack_from("=II", payload)
            msg, _ = read_string(payload, 8)
            log(f"protocol error on {oid} ({code}): {msg}")
            sys.exit(1)

    def bind(self, name, iface, version, handler):
        oid = self.wire.new_id(handler)
        self.wire.send(self.registry, 0, struct.pack("=I", name) + wl_string(iface) + struct.pack("=II", version, oid))
        return oid

    def on_registry(self, opcode, payload):
        if opcode == 0:  # global
            name = struct.unpack_from("=I", payload)[0]
            iface, off = read_string(payload, 4)
            version = struct.unpack_from("=I", payload, off)[0]
            if iface == "zwlr_gamma_control_manager_v1":
                self.manager = self.bind(name, iface, 1, lambda o, p: None)
                self.manager_seen = True
            elif iface == "wl_output":
                if version < 4:
                    log("wl_output < v4: no names, '*' only")
                out = Output(self, name, 0)
                out.oid = self.bind(name, iface, min(version, 4), out.on_event)
                self.outputs[name] = out
                self.dirty = True
        elif opcode == 1:  # global_remove
            name = struct.unpack_from("=I", payload)[0]
            out = self.outputs.pop(name, None)
            if out:
                self.release(out)
                self.outputs_changed()

    def on_initial_sync(self, opcode, payload):
        self.status = "ready" if self.manager_seen else "unsupported"
        emit(self.status)
        if not self.manager_seen:
            sys.exit(3)
        self.outputs_changed()

    def snapshot(self):
        """What a newly connected relay has to hear."""
        lines = [f"stamp {STAMP}"]
        if self.status:
            lines.append(self.status)
        if self.last_names is not None:
            lines.append(f"outputs {self.last_names}")
        lines += [f"failed {o.name}" for o in self.outputs.values() if o.failed]
        return lines

    def outputs_changed(self):
        names = ",".join(sorted(o.name for o in self.outputs.values() if o.name))
        if names != self.last_names:
            self.last_names = names
            emit(f"outputs {names}")
        self.apply_targets(time.monotonic(), 0)

    def target_of(self, out):
        return self.temps.get(out.name, self.temps.get("*", NEUTRAL))

    def apply_targets(self, now, fade):
        for out in self.outputs.values():
            out.retarget(self.target_of(out), fade, now)
        self.dirty = True

    def acquire(self, out, now):
        if out.ctrl or not self.manager:
            return
        if out.failed:
            if out.fail_count > RETRIES or now < out.retry_at:
                return
            out.failed = False
        out.ctrl = self.wire.new_id(out.on_ctrl)
        self.wire.send(self.manager, 0, struct.pack("=II", out.ctrl, out.oid))  # get_gamma_control

    def release(self, out):
        if out.ctrl:
            self.wire.send(out.ctrl, 1)  # destroy → the compositor restores identity
        out.ctrl = 0
        out.size = 0
        out.sent = None

    def upload(self, out, k):
        data = ramp(out.size, k)
        fd = os.memfd_create("flicker-gamma", os.MFD_CLOEXEC)
        try:
            os.write(fd, data)
            os.lseek(fd, 0, os.SEEK_SET)  # smithay reads from the shared offset
            self.wire.send(out.ctrl, 0, fd=fd)  # set_gamma
        finally:
            os.close(fd)

    def step(self):
        """Paint every output once; returns True while a fade still runs."""
        now = time.monotonic()
        busy = False
        for out in self.outputs.values():
            k = out.current(now)
            busy |= out.fading
            rounded = int(round(k / 10) * 10)
            if rounded >= NEUTRAL - 5 and out.target >= NEUTRAL and not out.fading:
                if out.ctrl:
                    self.release(out)
                out.shown = NEUTRAL
                continue
            self.acquire(out, now)
            busy |= out.failed and out.fail_count <= RETRIES
            if not out.size or out.sent == rounded:
                continue
            self.upload(out, rounded)
            out.sent = rounded
            out.shown = k
        self.dirty = busy
        return busy

    def command(self, line):
        try:
            msg = json.loads(line)
        except ValueError:
            log("bad command:", line.strip())
            return
        now = time.monotonic()
        if msg.get("reapply"):
            for out in self.outputs.values():
                out.sent = None
                out.fail_count = 0
                out.retry_at = 0
            self.dirty = True
        if "temps" in msg:
            temps = {str(k): max(1000, min(10000, int(v))) for k, v in msg["temps"].items()}
            self.temps = temps
            for out in self.outputs.values():
                out.fail_count = 0  # a new target = another round of retries
                out.retry_at = 0
            self.apply_targets(now, max(0, float(msg.get("fade", 0))))


def serve(listener):
    """Daemon loop: the Wayland connection + every relay's commands."""
    gd = Gammad()
    sel = selectors.DefaultSelector()
    sel.register(gd.wire.sock, selectors.EVENT_READ, "wl")
    sel.register(listener, selectors.EVENT_READ, "accept")
    pending = {}
    alone_since = time.monotonic()
    last = 0.0
    while True:
        now = time.monotonic()
        timeout = None
        if gd.dirty:
            timeout = max(0.0, last + FRAME_S - now)
        if not CLIENTS:
            left = alone_since + LINGER_S - now
            if left <= 0:
                log("no shell for", LINGER_S, "s, exiting")
                return 0
            timeout = left if timeout is None else min(timeout, left)
        for key, _ in sel.select(timeout):
            if key.data == "wl":
                if not gd.wire.read():
                    log("compositor connection closed")
                    return 1
            elif key.data == "accept":
                c, _ = listener.accept()
                CLIENTS.append(c)
                pending[c] = b""
                sel.register(c, selectors.EVENT_READ, "client")
                for line in gd.snapshot():
                    c.sendall((line + "\n").encode())
            else:
                c = key.fileobj
                try:
                    chunk = c.recv(65536)
                except OSError:
                    chunk = b""
                if not chunk:
                    sel.unregister(c)
                    c.close()
                    pending.pop(c, None)
                    if c in CLIENTS:
                        CLIENTS.remove(c)
                    if not CLIENTS:
                        alone_since = time.monotonic()
                    continue
                pending[c] += chunk
                *lines, pending[c] = pending[c].split(b"\n")
                for line in lines:
                    if line.strip() == b'{"quit": true}':
                        log("replaced by a newer gammad.py")
                        return 0
                    if line.strip():
                        gd.command(line.decode(errors="replace"))
        if gd.dirty and time.monotonic() - last >= FRAME_S:
            gd.step()
            last = time.monotonic()


def spawn_daemon(listener):
    """Detach (double fork, own session: not killed with the shell's
    process), stdio to $XDG_RUNTIME_DIR/flicker/gammad.log."""
    pid = os.fork()
    if pid:
        os.waitpid(pid, 0)
        return
    os.setsid()
    if os.fork():
        os._exit(0)
    logdir = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "flicker")
    os.makedirs(logdir, exist_ok=True)
    out = os.open(os.path.join(logdir, "gammad.log"), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    null = os.open(os.devnull, os.O_RDONLY)
    os.dup2(null, 0)
    os.dup2(out, 1)
    os.dup2(out, 2)
    code = 1
    try:
        code = serve(listener)
    except SystemExit as e:
        code = e.code if isinstance(e.code, int) else 1
    except Exception as e:  # noqa: BLE001 — logged, the relays respawn it
        log("crashed:", repr(e))
    os._exit(code)


def connect():
    """A socket to a current daemon, starting / replacing it as needed."""
    for _ in range(100):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            s.connect(SOCK)
        except OSError:
            s.close()
            lst = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                lst.bind(SOCK)
            except OSError:  # another relay won the race
                lst.close()
                time.sleep(0.05)
                continue
            lst.listen(8)
            spawn_daemon(lst)
            lst.close()
            continue
        head = b""
        try:
            while not head.endswith(b"\n"):  # byte by byte: the rest stays queued
                b = s.recv(1)
                if not b:
                    break
                head += b
        except OSError:
            head = b""
        if not head:  # died on the way (logged in gammad.log): start another
            s.close()
            time.sleep(0.2)
            continue
        first = head.decode().split()
        if first[:1] == ["stamp"] and first[1:] == [STAMP]:
            return s
        # Older code: replace it (a short identity flash, code changes only).
        s.sendall(b'{"quit": true}\n')
        try:
            s.settimeout(2)
            while s.recv(4096):
                pass
        except OSError:
            pass
        s.close()
    raise SystemExit("cannot reach the gamma daemon")


def main():
    s = connect()
    sel = selectors.DefaultSelector()
    sel.register(s, selectors.EVENT_READ, "daemon")
    sel.register(sys.stdin.fileno(), selectors.EVENT_READ, "in")
    buf = b""
    while True:
        for key, _ in sel.select():
            if key.data == "daemon":
                chunk = s.recv(65536)
                if not chunk:
                    log("daemon gone")
                    return 1
                buf += chunk
                *lines, buf = buf.split(b"\n")
                for line in lines:
                    text = line.decode(errors="replace")
                    if text.startswith("stamp "):
                        continue
                    print(text, flush=True)
                    if text == "unsupported":
                        return 3
            else:
                chunk = os.read(sys.stdin.fileno(), 65536)
                if not chunk:
                    return 0
                s.sendall(chunk)


if __name__ == "__main__":
    sys.exit(main())
