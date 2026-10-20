#!/usr/bin/env python3
"""Forget WirePlumber's remembered stream outputs ("target" of entries in
~/.local/state/wireplumber/stream-properties), for settings → Sound → App
outputs. WirePlumber keeps that file in memory and rewrites it, so it is
stopped, edited and started again (sound pauses for about a second).

    forget-routes.py <entry key>...   e.g. "Output/Audio:application.name:Zen"
    forget-routes.py --all
"""
import json
import os
import subprocess
import sys


def main():
    keys = sys.argv[1:]
    if not keys:
        print(__doc__, file=sys.stderr)
        return 2
    state = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"),
                         "wireplumber", "stream-properties")
    subprocess.run(["systemctl", "--user", "stop", "wireplumber"], check=True)
    try:
        with open(state) as f:
            lines = f.read().splitlines()
        out = []
        for line in lines:
            key, sep, value = line.partition("=")
            if sep and (keys == ["--all"] or key in keys):
                try:
                    data = json.loads(value)
                except ValueError:
                    data = None
                if isinstance(data, dict) and "target" in data:
                    del data["target"]
                    line = key + "=" + json.dumps(data)
            out.append(line)
        tmp = state + ".flicker"
        with open(tmp, "w") as f:
            f.write("\n".join(out) + "\n")
        os.replace(tmp, state)
    finally:
        subprocess.run(["systemctl", "--user", "start", "wireplumber"], check=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
