#!/usr/bin/env python3
"""Text caret tracker for the keyboard pill (services/KeyboardIndicator.qml).

A minimal Wayland client (stdlib only, raw wire protocol, no fds) that binds
zwp_input_method_manager_v2 as the seat's input method WITHOUT grabbing the
keyboard and creates one input-popup surface (no buffer, never shown). The
compositor then reports:
  - activate / deactivate (+ done): a text field gained / lost focus
  - text_input_rectangle: the caret rectangle, in the FOCUSED SURFACE's local
    coordinates (smithay forwards text-input-v3 set_cursor_rectangle as is)
stdout, one JSON object per line:
  {"active": true|false}            on done after (de)activate
  {"rect": [x, y, w, h]}            caret moved (surface-local logical px)
Exit 3 = another input method owns the seat (fcitx/ibus): `unavailable`.
"""
import json
import os
import socket
import struct
import sys

SOCK = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid()),
                    os.environ.get("WAYLAND_DISPLAY", "wayland-0"))


def out(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def enc_str(s):
    b = s.encode() + b"\0"
    return struct.pack("<I", len(b)) + b + b"\0" * ((4 - len(b) % 4) % 4)


class Conn:
    def __init__(self):
        self.s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.s.connect(SOCK)
        self.next_id = 2  # 1 = wl_display
        self.kinds = {1: "wl_display"}
        self.buf = b""

    def new(self, kind):
        i = self.next_id
        self.next_id += 1
        self.kinds[i] = kind
        return i

    def send(self, obj, op, payload=b""):
        self.s.sendall(struct.pack("<II", obj, ((8 + len(payload)) << 16) | op) + payload)

    def events(self):
        while True:
            while len(self.buf) >= 8:
                obj, so = struct.unpack_from("<II", self.buf)
                size = so >> 16
                if len(self.buf) < size:
                    break
                body = self.buf[8:size]
                self.buf = self.buf[size:]
                yield obj, so & 0xFFFF, body
            data = self.s.recv(65536)
            if not data:
                return
            self.buf += data


def read_str(body, off):
    n = struct.unpack_from("<I", body, off)[0]
    s = body[off + 4:off + 4 + n - 1].decode(errors="replace")
    return s, off + 4 + ((n + 3) & ~3)


def main():
    c = Conn()
    registry = c.new("wl_registry")
    c.send(1, 1, struct.pack("<I", registry))  # wl_display.get_registry
    sync = c.new("wl_callback")
    c.send(1, 0, struct.pack("<I", sync))  # wl_display.sync

    globs = {}
    ev = c.events()
    for obj, op, body in ev:
        kind = c.kinds.get(obj)
        if kind == "wl_registry" and op == 0:
            name = struct.unpack_from("<I", body)[0]
            iface, off = read_str(body, 4)
            ver = struct.unpack_from("<I", body, off)[0]
            globs.setdefault(iface, (name, ver))
        elif kind == "wl_display" and op == 0:
            _, code = struct.unpack_from("<II", body)
            sys.stderr.write("wayland error %d: %s\n" % (code, read_str(body, 8)[0]))
            return 1
        elif obj == sync:
            break

    need = ("wl_compositor", "wl_seat", "zwp_input_method_manager_v2")
    missing = [n for n in need if n not in globs]
    if missing:
        sys.stderr.write("caret: compositor lacks %s\n" % ", ".join(missing))
        return 2

    def bind(iface, ver):
        i = c.new(iface)
        name = globs[iface][0]
        c.send(registry, 0, struct.pack("<I", name) + enc_str(iface) + struct.pack("<II", ver, i))
        return i

    comp = bind("wl_compositor", 1)
    seat = bind("wl_seat", 1)
    mgr = bind("zwp_input_method_manager_v2", 1)
    im = c.new("zwp_input_method_v2")
    c.send(mgr, 0, struct.pack("<II", seat, im))  # get_input_method
    surf = c.new("wl_surface")
    c.send(comp, 0, struct.pack("<I", surf))  # create_surface
    popup = c.new("zwp_input_popup_surface_v2")
    c.send(im, 4, struct.pack("<II", popup, surf))  # get_input_popup_surface

    pending = None
    active = False
    for obj, op, body in ev:
        kind = c.kinds.get(obj)
        if kind == "zwp_input_method_v2":
            if op == 0:
                pending = True
            elif op == 1:
                pending = False
            elif op == 5:  # done
                if pending is not None and pending != active:
                    active = pending
                    out({"active": active})
                pending = None
            elif op == 6:
                sys.stderr.write("caret: another input method is running\n")
                return 3
        elif kind == "zwp_input_popup_surface_v2" and op == 0:
            out({"rect": list(struct.unpack_from("<iiii", body))})
        elif kind == "wl_display" and op == 0:
            _, code = struct.unpack_from("<II", body)
            sys.stderr.write("wayland error %d: %s\n" % (code, read_str(body, 8)[0]))
            return 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (BrokenPipeError, KeyboardInterrupt):
        sys.exit(0)
