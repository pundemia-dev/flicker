#!/bin/sh
# Wi‑Fi helpers for services/Network.qml (the QS Wi‑Fi panel). nmcli -t
# output; secrets come in as arguments (like `nmcli device wifi connect`).
#
#   saved                      saved Wi‑Fi profiles: blocks of
#                              connection.uuid / 802-11-wireless.ssid /
#                              802-11-wireless-security.key-mgmt
#   details                    current link: device show fields, ---, the
#                              in-use AP line (IN-USE,CHAN,FREQ,RATE,SECURITY,BSSID)
#   share <uuid> <type> <ssid> line 1 = the saved password, line 2 = a Wi‑Fi
#                              QR code (PNG, base64); type WPA|SAE (nopass
#                              when the profile has no password)
#   psk <uuid> <password>      new password into a saved profile, then up
#   eap <ssid> <user> <password> [uuid]
#                              WPA‑Enterprise (PEAP / MSCHAPv2): new profile
#                              or new credentials for a saved one, then up
#                              (a new profile is deleted again if that fails)
#   hidden <ssid> [password]   hidden network: a profile with wifi.hidden
#                              (iwd under NM refuses `device wifi connect
#                              ... hidden yes`: "'ssid' scan option not
#                              supported"), then up; deleted again if that fails
#   down                       deactivate the active Wi‑Fi profile
#   forget <uuid>...           delete saved profiles
#   ping                       latency of an HTTP probe (whatever route is
#                              up): "OK:<ms>" / "ERR:timeout"
#   speedtest                  speedtest-cli --simple, or ERR_MISSING
set -u
wait=40

case "${1:-}" in
saved)
    u=$(nmcli -t -f UUID,TYPE connection show | grep ':802-11-wireless$' | cut -d: -f1)
    [ -z "$u" ] && exit 0
    # shellcheck disable=SC2086
    nmcli -t -f connection.uuid,802-11-wireless.ssid,802-11-wireless-security.key-mgmt connection show $u
    ;;
details)
    dev=$(nmcli -t -f DEVICE,TYPE device | grep ':wifi$' | head -n1 | cut -d: -f1)
    [ -z "$dev" ] && exit 1
    nmcli -t -f IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,GENERAL.HWADDR device show "$dev"
    echo ---
    nmcli -t -f IN-USE,CHAN,FREQ,RATE,SECURITY,BSSID device wifi list ifname "$dev" --rescan no | grep '^\*' | head -n1
    ;;
share)
    p=$(nmcli -s -g 802-11-wireless-security.psk connection show uuid "$2" 2>/dev/null)
    t=$3
    [ -z "$p" ] && t=nopass
    esc() { printf '%s' "$1" | sed 's/[\\;,:"]/\\&/g'; }
    printf '%s\n' "$p"
    printf 'WIFI:T:%s;S:%s;P:%s;;' "$t" "$(esc "$4")" "$(esc "$p")" | qrencode -t PNG -s 8 -m 1 -o - | base64 -w0
    ;;
psk)
    nmcli connection modify uuid "$2" wifi-sec.psk "$3" && nmcli -w $wait connection up uuid "$2"
    ;;
eap)
    if [ -n "${5:-}" ]; then
        nmcli connection modify uuid "$5" 802-1x.identity "$3" 802-1x.password "$4" \
            && nmcli -w $wait connection up uuid "$5"
    else
        out=$(nmcli connection add type wifi con-name "$2" ssid "$2" wifi-sec.key-mgmt wpa-eap \
            802-1x.eap peap 802-1x.phase2-auth mschapv2 802-1x.identity "$3" 802-1x.password "$4") || exit 1
        u=$(printf '%s' "$out" | sed -n 's/.*(\([0-9a-f-]\{36\}\)).*/\1/p')
        nmcli -w $wait connection up uuid "$u" && exit 0
        rc=$?
        nmcli connection delete uuid "$u" >/dev/null
        exit $rc
    fi
    ;;
hidden)
    if [ -n "${3:-}" ]; then
        out=$(nmcli connection add type wifi con-name "$2" ssid "$2" wifi.hidden yes \
            wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$3") || exit 1
    else
        out=$(nmcli connection add type wifi con-name "$2" ssid "$2" wifi.hidden yes) || exit 1
    fi
    u=$(printf '%s' "$out" | sed -n 's/.*(\([0-9a-f-]\{36\}\)).*/\1/p')
    nmcli -w $wait connection up uuid "$u" && exit 0
    rc=$?
    nmcli connection delete uuid "$u" >/dev/null
    exit $rc
    ;;
down)
    u=$(nmcli -t -f UUID,TYPE connection show --active | grep ':802-11-wireless$' | head -n1 | cut -d: -f1)
    [ -n "$u" ] && nmcli connection down uuid "$u"
    ;;
forget)
    shift
    for u in "$@"; do nmcli connection delete uuid "$u"; done
    ;;
ping)
    t=$(curl -4 -s -o /dev/null -w '%{time_total}' --connect-timeout 5 -m 6 \
        http://cp.cloudflare.com/generate_204) || { echo "ERR:timeout"; exit 1; }
    echo "OK:$(awk -v t="$t" 'BEGIN { printf "%d", t * 1000 }')"
    ;;
speedtest)
    command -v speedtest-cli >/dev/null || { echo ERR_MISSING; exit 1; }
    speedtest-cli --simple 2>/dev/null || { echo ERR_FAILED; exit 1; }
    ;;
*)
    echo "usage: wifi.sh saved|details|share|psk|eap|down|forget|ping|speedtest" >&2
    exit 2
    ;;
esac
