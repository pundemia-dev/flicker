#!/usr/bin/env python3
"""Session side of the idle chain (services/Idle.qml): the D-Bus pieces QML
cannot reach. One line per fact on stdout, one command per line on stdin.

stdout:
  ready
  screensaver <json [{app, reason}]>   org.freedesktop.ScreenSaver holders
                                       (Chromium/Electron/Steam/VLC/Wine…)
  screensaver busy                     the name belongs to someone else
  logind <json [{who, why}]>           `systemd-inhibit --what=idle` holders
  sleep 1 | sleep 0                    logind PrepareForSleep
  lock | unlock                        `loginctl lock-session` / `unlock-session`
  activity                             ScreenSaver.SimulateUserActivity
  ramped                               a backlight ramp reached its target
stdin:
  release              drop the sleep delay inhibitor (the lock is up); taken
                       again after the wake
  idlehint 0|1  lockedhint 0|1  active 0|1 (ScreenSaver ActiveChanged)
  hold <class> <device> <raw>   the user's level: put back on exit, so a dim
                       never outlives the shell (reload, crash)
  unhold
  ramp <class> <device> <raw> <ms>   ease the backlight there (logind
                       SetBrightness, no process per step)
"""
import json
import os
import signal
import sys

from gi.repository import Gio, GLib

try:
    from gi.repository import GLibUnix
    signal_add = GLibUnix.signal_add
except ImportError:
    signal_add = GLib.unix_signal_add

LOGIN = "org.freedesktop.login1"
LOGIN_PATH = "/org/freedesktop/login1"
MANAGER = "org.freedesktop.login1.Manager"
SESSION = "org.freedesktop.login1.Session"
SS_NAME = "org.freedesktop.ScreenSaver"
SS_PATHS = ("/org/freedesktop/ScreenSaver", "/ScreenSaver")
SS_XML = """<node><interface name="org.freedesktop.ScreenSaver">
<method name="Inhibit"><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="u" direction="out"/></method>
<method name="UnInhibit"><arg type="u" direction="in"/></method>
<method name="GetActive"><arg type="b" direction="out"/></method>
<method name="SetActive"><arg type="b" direction="in"/><arg type="b" direction="out"/></method>
<method name="GetActiveTime"><arg type="u" direction="out"/></method>
<method name="GetSessionIdleTime"><arg type="u" direction="out"/></method>
<method name="SimulateUserActivity"/>
<signal name="ActiveChanged"><arg type="b"/></signal>
</interface></node>"""


def out(*parts):
    print(*parts, flush=True)


class Idled:
    def __init__(self):
        self.loop = GLib.MainLoop()
        self.system = Gio.bus_get_sync(Gio.BusType.SYSTEM)
        self.session_bus = Gio.bus_get_sync(Gio.BusType.SESSION)
        self.session_path = self.call(MANAGER, LOGIN_PATH, "GetSession", GLib.Variant("(s)", ("auto",)))
        self.session_path = self.session_path[0] if self.session_path else None
        self.delay_fd = -1
        self.cookies = {}  # cookie -> (sender, app, reason)
        self.next_cookie = 1
        self.active = False
        self.active_since = 0
        self.hold = None  # (class, device, raw)
        self.ramp_id = 0
        self.logind_last = None
        self.buf = b""

        self.system.signal_subscribe(LOGIN, MANAGER, "PrepareForSleep", LOGIN_PATH, None,
                                     Gio.DBusSignalFlags.NONE, self.on_sleep)
        self.system.signal_subscribe(LOGIN, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                                     LOGIN_PATH, None, Gio.DBusSignalFlags.NONE,
                                     lambda *a: self.refresh_logind())
        if self.session_path:
            for sig in ("Lock", "Unlock"):
                self.system.signal_subscribe(LOGIN, SESSION, sig, self.session_path, None,
                                             Gio.DBusSignalFlags.NONE,
                                             lambda *a, s=sig: out(s.lower()))
        self.session_bus.signal_subscribe("org.freedesktop.DBus", "org.freedesktop.DBus",
                                          "NameOwnerChanged", "/org/freedesktop/DBus", None,
                                          Gio.DBusSignalFlags.NONE, self.on_owner_changed)
        self.take_delay()
        Gio.bus_own_name_on_connection(self.session_bus, SS_NAME, Gio.BusNameOwnerFlags.DO_NOT_QUEUE,
                                       self.on_name_acquired, self.on_name_lost)
        self.refresh_logind()
        # BlockInhibited change signals are not guaranteed: a slow poll backs them up.
        GLib.timeout_add_seconds(30, lambda: self.refresh_logind() or True)
        GLib.io_add_watch(sys.stdin.fileno(), GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, self.on_stdin)
        for s in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            signal_add(GLib.PRIORITY_HIGH, s, self.quit)
        out("ready")

    # --- logind -----------------------------------------------------------
    def call(self, iface, path, method, args=None, reply=None, fds=False):
        try:
            if fds:
                return self.system.call_with_unix_fd_list_sync(
                    LOGIN, path, iface, method, args, GLib.VariantType(reply) if reply else None,
                    Gio.DBusCallFlags.NONE, -1, None, None)
            return self.system.call_sync(LOGIN, path, iface, method, args,
                                         GLib.VariantType(reply) if reply else None,
                                         Gio.DBusCallFlags.NONE, -1, None).unpack()
        except GLib.Error as e:
            print(f"idled: {method}: {e.message}", file=sys.stderr, flush=True)
            return None

    def take_delay(self):
        if self.delay_fd >= 0:
            return
        r = self.call(MANAGER, LOGIN_PATH, "Inhibit",
                      GLib.Variant("(ssss)", ("sleep", "Flicker", "Lock the screen before sleep", "delay")),
                      "(h)", fds=True)
        if r is None:
            return
        result, fdlist = r
        self.delay_fd = fdlist.get(result.unpack()[0])

    def release_delay(self):
        if self.delay_fd >= 0:
            os.close(self.delay_fd)
            self.delay_fd = -1

    def on_sleep(self, conn, sender, path, iface, sig, params):
        going = params.unpack()[0]
        if not going:
            self.take_delay()
        out("sleep", 1 if going else 0)

    def refresh_logind(self):
        r = self.call(MANAGER, LOGIN_PATH, "ListInhibitors", None, "(a(ssssuu))")
        if r is None:
            return
        me = os.getpid()
        held = [{"who": who, "why": why} for what, who, why, mode, uid, pid in r[0]
                if "idle" in what.split(":") and mode == "block" and pid != me]
        line = json.dumps(held, ensure_ascii=False)
        if line != self.logind_last:
            self.logind_last = line
            out("logind", line)

    def hint(self, method, on):
        if self.session_path:
            self.call(SESSION, self.session_path, method, GLib.Variant("(b)", (on,)))

    def set_brightness(self, cls, dev, raw):
        if self.session_path:
            self.call(SESSION, self.session_path, "SetBrightness", GLib.Variant("(ssu)", (cls, dev, max(0, int(raw)))))

    # --- backlight ramp ---------------------------------------------------
    def ramp(self, cls, dev, to, ms):
        if self.ramp_id:
            GLib.source_remove(self.ramp_id)
            self.ramp_id = 0
        try:
            with open(f"/sys/class/{cls}/{dev}/brightness") as f:
                start = int(f.read().strip())
        except (OSError, ValueError):
            start = to
        if ms <= 0 or start == to:
            self.set_brightness(cls, dev, to)
            out("ramped")
            return
        t0 = GLib.get_monotonic_time()
        last = [start]

        def step():
            p = min(1.0, (GLib.get_monotonic_time() - t0) / (ms * 1000))
            e = 1 - (1 - p) ** 3  # OutCubic: the change is felt at once, then settles
            v = round(start + (to - start) * e)
            if v != last[0]:
                last[0] = v
                self.set_brightness(cls, dev, v)
            if p >= 1:
                self.ramp_id = 0
                out("ramped")
                return False
            return True

        self.ramp_id = GLib.timeout_add(16, step)

    # --- org.freedesktop.ScreenSaver --------------------------------------
    def on_name_acquired(self, conn, name):
        node = Gio.DBusNodeInfo.new_for_xml(SS_XML)
        for p in SS_PATHS:
            conn.register_object(p, node.interfaces[0], self.on_ss_call, None, None)
        self.emit_screensaver()

    def on_name_lost(self, conn, name):
        out("screensaver busy")

    def on_ss_call(self, conn, sender, path, iface, method, params, inv):
        args = params.unpack()
        if method == "Inhibit":
            cookie = self.next_cookie
            self.next_cookie += 1
            self.cookies[cookie] = (sender, args[0], args[1])
            inv.return_value(GLib.Variant("(u)", (cookie,)))
            self.emit_screensaver()
        elif method == "UnInhibit":
            if self.cookies.pop(args[0], None):
                self.emit_screensaver()
            inv.return_value(None)
        elif method == "GetActive":
            inv.return_value(GLib.Variant("(b)", (self.active,)))
        elif method == "SetActive":
            # Locking from here would skip the shell's lock animation path:
            # only "lock" is honoured, as a request the shell handles.
            if args[0]:
                out("lock")
            inv.return_value(GLib.Variant("(b)", (False,)))
        elif method == "GetActiveTime":
            t = int(GLib.get_monotonic_time() / 1e6 - self.active_since) if self.active else 0
            inv.return_value(GLib.Variant("(u)", (t,)))
        elif method == "GetSessionIdleTime":
            inv.return_value(GLib.Variant("(u)", (0,)))
        elif method == "SimulateUserActivity":
            out("activity")
            inv.return_value(None)

    def on_owner_changed(self, conn, sender, path, iface, sig, params):
        name, old, new = params.unpack()
        if new or not old:
            return
        gone = [c for c, v in self.cookies.items() if v[0] == old]
        for c in gone:
            del self.cookies[c]
        if gone:
            self.emit_screensaver()

    def emit_screensaver(self):
        held = [{"app": a, "reason": r} for _, a, r in self.cookies.values()]
        out("screensaver", json.dumps(held, ensure_ascii=False))

    def set_active(self, on):
        if on == self.active:
            return
        self.active = on
        self.active_since = GLib.get_monotonic_time() / 1e6
        for p in SS_PATHS:
            try:
                self.session_bus.emit_signal(None, p, SS_NAME, "ActiveChanged", GLib.Variant("(b)", (on,)))
            except GLib.Error:
                pass

    # --- commands ---------------------------------------------------------
    def on_stdin(self, fd, cond):
        # os.read, not readline: lines arriving together would stay in
        # Python's buffer with the fd no longer readable.
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            chunk = b""
        if not chunk:
            self.quit()
            return False
        self.buf += chunk
        while b"\n" in self.buf:
            line, self.buf = self.buf.split(b"\n", 1)
            self.command(line.decode(errors="replace"))
        return True

    def command(self, line):
        a = line.split()
        if not a:
            return
        cmd = a[0]
        try:
            if cmd == "release":
                self.release_delay()
            elif cmd == "idlehint":
                self.hint("SetIdleHint", a[1] == "1")
            elif cmd == "lockedhint":
                self.hint("SetLockedHint", a[1] == "1")
            elif cmd == "active":
                self.set_active(a[1] == "1")
            elif cmd == "hold":
                self.hold = (a[1], a[2], int(a[3]))
            elif cmd == "unhold":
                self.hold = None
            elif cmd == "ramp":
                self.ramp(a[1], a[2], int(a[3]), int(a[4]))
        except (IndexError, ValueError) as e:
            print(f"idled: bad command {line.strip()!r}: {e}", file=sys.stderr, flush=True)

    def quit(self):
        if self.ramp_id:
            GLib.source_remove(self.ramp_id)
        if self.hold:
            self.set_brightness(*self.hold)
        self.release_delay()
        self.loop.quit()
        return False


if __name__ == "__main__":
    Idled().loop.run()
