#!/usr/bin/env -S uv run --script --quiet
# /// script
# requires-python = ">=3.11"
# dependencies = ["pywayland"]
# ///
"""Nudge the pointer by ±1px via zwlr_virtual_pointer_v1.

niri does not send wl_pointer.enter to a newly mapped layer surface until the
pointer physically moves, so the capture overlay can't know the cursor
position at open — no crosshair/loupe/bubble until the user wiggles the
mouse. A 1px out-and-back virtual motion forces niri to recompute pointer
focus and deliver enter (with coordinates) to the overlay immediately.

Bindings for the wlr protocol are generated once with pywayland-scanner into
the pShell cache dir (the protocol XML is embedded below; it ships with
wlr-protocols, which isn't packaged on this system).
"""

import os
import subprocess
import sys
import time
from pathlib import Path

PROTOCOL_XML = """<?xml version="1.0" encoding="UTF-8"?>
<protocol name="wlr_virtual_pointer_unstable_v1">
  <interface name="zwlr_virtual_pointer_v1" version="2">
    <description summary="virtual pointer">
      This protocol allows clients to emulate a physical pointer device. The
      requests are mostly mirror opposites of those specified in wl_pointer.
    </description>
    <enum name="error">
      <entry name="invalid_axis" value="0"
        summary="client sent invalid axis enumeration value" />
      <entry name="invalid_axis_source" value="1"
        summary="client sent invalid axis source enumeration value" />
    </enum>
    <request name="motion">
      <arg name="time" type="uint" summary="timestamp with millisecond granularity"/>
      <arg name="dx" type="fixed" summary="displacement on the x-axis"/>
      <arg name="dy" type="fixed" summary="displacement on the y-axis"/>
    </request>
    <request name="motion_absolute">
      <arg name="time" type="uint" summary="timestamp with millisecond granularity"/>
      <arg name="x" type="uint" summary="position on the x-axis"/>
      <arg name="y" type="uint" summary="position on the y-axis"/>
      <arg name="x_extent" type="uint" summary="extent of the x-axis"/>
      <arg name="y_extent" type="uint" summary="extent of the y-axis"/>
    </request>
    <request name="button">
      <arg name="time" type="uint" summary="timestamp with millisecond granularity"/>
      <arg name="button" type="uint" summary="button that produced the event"/>
      <arg name="state" type="uint" enum="wl_pointer.button_state" summary="physical state of the button"/>
    </request>
    <request name="axis">
      <arg name="time" type="uint" summary="timestamp with millisecond granularity"/>
      <arg name="axis" type="uint" enum="wl_pointer.axis" summary="axis type"/>
      <arg name="value" type="fixed" summary="length of vector in touchpad coordinates"/>
    </request>
    <request name="frame">
    </request>
    <request name="axis_source">
      <arg name="axis_source" type="uint" enum="wl_pointer.axis_source" summary="source of the axis event"/>
    </request>
    <request name="axis_stop">
      <arg name="time" type="uint" summary="timestamp with millisecond granularity"/>
      <arg name="axis" type="uint" enum="wl_pointer.axis" summary="the axis stopped with this event"/>
    </request>
    <request name="axis_discrete">
      <arg name="time" type="uint" summary="timestamp with millisecond granularity"/>
      <arg name="axis" type="uint" enum="wl_pointer.axis" summary="axis type"/>
      <arg name="value" type="fixed" summary="length of vector in touchpad coordinates"/>
      <arg name="discrete" type="int" summary="number of steps"/>
    </request>
    <request name="destroy" type="destructor" since="1">
    </request>
  </interface>
  <interface name="zwlr_virtual_pointer_manager_v1" version="2">
    <description summary="virtual pointer manager">
      This object allows clients to create individual virtual pointer objects.
    </description>
    <request name="create_virtual_pointer">
      <arg name="seat" type="object" interface="wl_seat" allow-null="true"/>
      <arg name="id" type="new_id" interface="zwlr_virtual_pointer_v1"/>
    </request>
    <request name="destroy" type="destructor" since="1">
    </request>
    <request name="create_virtual_pointer_with_output" since="2">
      <arg name="seat" type="object" interface="wl_seat" allow-null="true"/>
      <arg name="output" type="object" interface="wl_output" allow-null="true"/>
      <arg name="id" type="new_id" interface="zwlr_virtual_pointer_v1"/>
    </request>
  </interface>
</protocol>
"""

WAYLAND_CORE_XML = "/usr/share/wayland/wayland.xml"


def ensure_bindings() -> Path:
    cache = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "pillShell" / "vptr-bindings"
    marker = cache / "gen" / "wlr_virtual_pointer_unstable_v1" / "__init__.py"
    if not marker.exists():
        gen = cache / "gen"
        gen.mkdir(parents=True, exist_ok=True)
        xml = cache / "wlr-virtual-pointer-unstable-v1.xml"
        xml.write_text(PROTOCOL_XML)
        subprocess.run(
            ["pywayland-scanner", "--input", WAYLAND_CORE_XML, str(xml), "--output-dir", str(gen)],
            check=True,
            capture_output=True,
        )
        (gen / "__init__.py").touch()
    return cache


def main() -> int:
    cache = ensure_bindings()
    sys.path.insert(0, str(cache))
    from pywayland.client import Display

    from gen.wlr_virtual_pointer_unstable_v1 import ZwlrVirtualPointerManagerV1

    display = Display()
    display.connect()
    try:
        registry = display.get_registry()
        found = {}

        def on_global(_reg, name, iface, version):
            if iface == "zwlr_virtual_pointer_manager_v1":
                found["mgr"] = registry.bind(name, ZwlrVirtualPointerManagerV1, min(version, 1))

        registry.dispatcher["global"] = on_global
        display.roundtrip()
        if "mgr" not in found:
            print("zwlr_virtual_pointer_manager_v1 not available", file=sys.stderr)
            return 1

        vp = found["mgr"].create_virtual_pointer(None)
        t = int(time.monotonic() * 1000) & 0xFFFFFFFF
        vp.motion(t, 1.0, 1.0)
        vp.frame()
        vp.motion(t + 1, -1.0, -1.0)
        vp.frame()
        display.roundtrip()
        vp.destroy()
    finally:
        display.disconnect()
    return 0


if __name__ == "__main__":
    sys.exit(main())
