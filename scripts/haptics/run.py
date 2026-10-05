#!/usr/bin/env python3
"""Haptics dispatcher for services/Haptics.qml.

Picks a backend and exec()s it, so the shell's stdin pipe goes straight to the
backend ("<effect> <intensity>" lines). Contract: docs/haptics.md.

  run.py --backend auto|<name>|<path> [--order a,b] [--options JSON]

A backend is a directory backends/<name>/ with an executable `backend`, or
any executable path. `backend probe` exit codes: 0 usable, 1 no hardware,
2 hardware present but not accessible (it prints a hint, e.g. the udev rule).
`backend run --options JSON` plays effects until stdin closes.

Exit 3 = no usable backend (the shell then stays silent, no respawn).
"""
import argparse, json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
NO_BACKEND = 3


def log(*a):
    print("[haptics]", *a, file=sys.stderr, flush=True)


def resolve(name):
    if os.sep in name:
        path = os.path.expanduser(name).rstrip(os.sep)
        if os.path.isdir(path):
            path = os.path.join(path, "backend")
        # Options key = the backend's directory name (like built-in ones).
        key = os.path.basename(os.path.dirname(path) if os.path.basename(path) == "backend" else path)
        return path, key
    return os.path.join(HERE, "backends", name, "backend"), name


def probe(path):
    try:
        r = subprocess.run([path, "probe"], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired) as e:
        return 1, str(e)
    return r.returncode, (r.stdout + r.stderr).strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--backend", default="auto")
    ap.add_argument("--order", default="evdev-haptic,apple-t2")
    ap.add_argument("--options", default="{}")
    ap.add_argument("--quiet", action="store_true", help="no hints when nothing is usable (re-probes)")
    a = ap.parse_args()
    try:
        options = json.loads(a.options) or {}
    except ValueError:
        options = {}

    names = [n for n in a.order.split(",") if n] if a.backend == "auto" else [a.backend]
    hints = []
    for n in names:
        path, key = resolve(n)
        if not os.access(path, os.X_OK):
            hints.append(f"{n}: {path} is not executable")
            continue
        code, out = probe(path)
        if code == 0:
            log(f"backend {key}" + (f" ({out})" if out else ""))
            os.execv(path, [path, "run", "--options", json.dumps(options.get(key, {}))])
        if code == 2:
            hints.append(f"{n}: {out}")
    if not a.quiet:
        for h in hints:
            log(h)
        if not hints:
            log("no haptic hardware found")
    sys.exit(NO_BACKEND)


if __name__ == "__main__":
    main()
