#!/usr/bin/env bash
# Restart the wallr daemon (services/Wallpaper, after an output's size /
# scale changes): wallr 0.6.4 follows a scale change with its viewport but
# keeps the old buffer — below 100 % the picture sits shrunk in a corner —
# and neither `wallr ipc reload` nor a set of the same path redraws it. A
# fresh daemon restores every output's last wallpaper at its current size.
# Runs detached (setsid): the daemon must outlive a shell reload.
wallr ipc stop >/dev/null 2>&1
for _ in $(seq 30); do
    pgrep -x wallr >/dev/null || break
    sleep 0.1
done
pkill -x wallr 2>/dev/null
exec wallr daemon >/dev/null 2>&1
