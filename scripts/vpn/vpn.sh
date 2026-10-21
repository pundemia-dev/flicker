#!/usr/bin/env bash
# VPN helpers for services/Vpn.qml (QS card `vpn` + its panel): sing-box
# as the system unit `sing-box.service` (runs `sing-box -C /etc/sing-box`,
# i.e. EVERY *.json in that directory is merged — config.json must stay the
# only one). Nodes = the outbounds of the first `selector` outbound, the
# active one = its `default`. Ported from the dots-hyprland (ii)
# virtualprivatenetwork.sh; subscriptions are parsed by sub_parser.py.
# Nodes sing-box cannot carry (gRPC: its lite transport fails against Xray
# servers; XHTTP) go to Xray (xray.service) behind local shadowsocks-2022 ports
# (xray_split.py, keyed), and while there are any xray.service
# starts / stops / restarts with sing-box.
# The configs hold the nodes' secrets: root:<unit user> 0640. What the panel
# needs (nodes, types, the active one, whether Xray is in use, the applied
# routing) is written next to them, secret-free, to /etc/flicker-vpn/view.json
# (0644).
# config.json = compose(base, routing, overlay) (routing.py): base = the
# subscription's config (sub_parser + xray_split, /etc/flicker-vpn/base.json,
# root 0600), routing = the shell's `vpn.routing` (direct / proxy / block
# rules by domain, IP, process, geosite / geoip), overlay = the user's own
# sing-box JSON (~/.config/flicker/vpn/custom.json), applied last. Root keeps
# copies of the applied routing / overlay and the geosite / geoip rule-sets
# (/etc/flicker-vpn/{routing,custom}.json, rules/), so a subscription update
# or a node switch recomposes the same way.
#
#   state              one JSON line: { installed, unit (systemctl
#                      is-active), enabled (autostart), online (a probe
#                      through it answered), profile, profiles:
#                      [{ tag, type }], subscription, killswitch (on),
#                      blocking (its table is up while sing-box is not),
#                      restarting (a root half is restarting the units
#                      itself: unit / blocking are in flux),
#                      routing (the applied one), customPending (the
#                      overlay file differs from the applied one) }
#   start | stop | restart
#                      systemctl start / stop / restart sing-box (polkit
#                      asks, unless the `setup` rule is installed)
#   enable | disable   autostart at boot (systemctl enable / disable;
#                      polkit always asks — unit files are not in the rule)
#   killswitch on|off  (root via pkexec) the kill switch: while it is on,
#                      starting sing-box also raises flicker-vpn-killswitch
#                      .service (a drop-in `Wants=`), an nftables table that
#                      rejects all outgoing traffic except loopback, the TUN,
#                      sing-box's / Xray's own (by uid) and the LAN (DNS
#                      excepted). It outlives a crashed sing-box: only `stop`
#                      takes it down ("release" in the panel).
#   select <tag>       make <tag> the selector default (root), restart the
#                      unit if it runs
#   subscribe <url>    remember the URL (user state, 0600), download it as
#                      the user, then (root) parse + `sing-box check` +
#                      install config.json, restart the unit if it runs
#   update             subscribe again with the remembered URL
#   apply [json] [refresh]
#                      routing (json = the shell's `vpn.routing`; without it
#                      the last one) + the overlay: validate, download the
#                      geosite / geoip rule-sets it needs (as the user; older
#                      than a day or `refresh` = again), then (root) compose,
#                      `sing-box check`, install, restart the unit if it runs
#   edit               the overlay in $VISUAL / $EDITOR (a skeleton first);
#                      `apply` puts it in force
#   ping              latency of an HTTP probe: "OK:<ms>" / "ERR:"
#   speedtest          speedtest-cli --simple (ERR_MISSING without it)
#   setup              (root, once; again after editing these scripts) a
#                      root-owned copy of them in /usr/local/lib/flicker-vpn
#                      and a polkit rule: the active local session of the
#                      calling user may, without a password, start / stop /
#                      restart sing-box.service, xray.service and the kill
#                      switch unit, and pkexec THE COPY for a node switch
#                      (_select) and a routing-only apply (_reroute) — never
#                      this user-writable script, never an overlay change
#                      or a subscription (those can make sing-box, which
#                      may read any file, serve or route anything).
#
# Root halves run from the copy while it matches these files (else from
# here, which polkit always asks for). What a password-free caller passes
# them is untrusted: routing as a JSON string (a path could name a
# root-only file), rule-set files read without following symlinks and only
# if the caller (PKEXEC_UID) owns them (routing.py install-rules).
set -u

config=/etc/sing-box/config.json
unit=sing-box
xray_config=/etc/xray/config.json
view=/etc/flicker-vpn/view.json
legacy_nodes=/etc/xray/flicker-nodes.tsv
probe=http://cp.cloudflare.com/generate_204
state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/flicker/vpn
sub_file=$state_dir/subscription
routing_file=$state_dir/routing.json
custom_file=${XDG_CONFIG_HOME:-$HOME/.config}/flicker/vpn/custom.json
rules_cache=${XDG_CACHE_HOME:-$HOME/.cache}/flicker/vpn/rules
base=/etc/flicker-vpn/base.json
routing_etc=/etc/flicker-vpn/routing.json
custom_etc=/etc/flicker-vpn/custom.json
rules_etc=/etc/flicker-vpn/rules
rule=/etc/polkit-1/rules.d/50-flicker-vpn.rules
sys_dir=/usr/local/lib/flicker-vpn
sys_files=(vpn.sh routing.py sub_parser.py xray_split.py)
ks_unit=flicker-vpn-killswitch
ks_unit_file=/etc/systemd/system/$ks_unit.service
ks_dropin=/etc/systemd/system/$unit.service.d/flicker-killswitch.conf
ks_rules=/etc/flicker-vpn/killswitch.nft
ks_table="inet flicker_killswitch"
# sub_parser.py names the TUN this; the kill switch lets it through.
tun_name=flicker-tun
self=$(realpath "$0")
here=$(dirname "$self")

# Root halves hold a lock on this file (lock_ops): `state` reports
# restarting (the panel holds the unit / kill switch it shows meanwhile).
# The kernel drops it with the holder, however it ends.
restart_mark=/run/flicker-vpn/restarting
unchecked=""

err() {
    echo "ERR:$*"
    exit 1
}

# The script pkexec runs: the root-owned copy while it is this one's (the
# password-free rule covers only it), else this one (polkit asks).
root_self() {
    local f
    for f in "${sys_files[@]}"; do
        cmp -s "$here/$f" "$sys_dir/$f" || { echo "$self"; return; }
    done
    echo "$sys_dir/vpn.sh"
}

# Xray carries some nodes (and is installed): it runs alongside sing-box.
uses_xray() {
    command -v xray >/dev/null || return 1
    jq -e '.xray == true' "$view" >/dev/null 2>&1 && return 0
    # Installed before the view existed: its node list.
    [ ! -e "$view" ] && [ -s "$legacy_nodes" ]
}

# sha256 of a file, "" when missing.
hash_of() {
    [ -f "$1" ] && sha256sum <"$1" | cut -c1-64
}

# The panel's view of $config: { profile, profiles: [{ tag, type (shown),
# base, xray, insecure }], xray, routing, customHash }. $1 = nodes moved to
# Xray ("tag<TAB>type<TAB>flags" lines; empty file / none = none).
view_of() {
    local xn='{}' r='{}'
    [ -s "${1:-}" ] && xn=$(jq -Rn '[inputs | split("\t") | select(length >= 2)
        | { key: .[0], value: { base: .[1], insecure: ((.[2] // "") | contains("insecure")) } }] | from_entries' "$1")
    [ -s "$routing_etc" ] && r=$(jq -c . "$routing_etc" 2>/dev/null || echo '{}')
    jq -c --arg ms "$(selector)" --argjson xn "$xn" --argjson r "$r" --arg ch "$(hash_of "$custom_etc")" '
        . as $c
        | ([$c.outbounds[]?, $c.endpoints[]?] | map(select(.tag | type == "string") | { key: .tag, value: .type }) | from_entries) as $types
        | ([$c.outbounds[]? | select(.type == "selector" and .tag == $ms)][0]) as $sel
        | def node($t): ($xn[$t]) as $x
            | if $x then { tag: $t, base: $x.base, xray: true, insecure: $x.insecure,
                           type: ($x.base + " · xray" + (if $x.insecure then " · ⚠ cert checked" else "" end)) }
              else { tag: $t, base: ($types[$t] // ""), xray: false, insecure: false, type: ($types[$t] // "") } end;
        {
            profile: (if $sel then ($sel.default // $sel.outbounds[0] // "") else "" end),
            profiles: (if $sel then [$sel.outbounds[]? | node(.)] else [] end),
            xray: ($xn != {}),
            routing: $r,
            customHash: $ch
        }' "$config"
}

# Root: compose $config's content from base $1 (routing $2, overlay $3) into
# $4, then `sing-box check` it. Prints ERR: and fails on either.
compose() {
    local out
    out=$(python3 -I "$here/routing.py" compose "$1" "$2" "$3" "$rules_etc" "$4") || { echo "$out"; return 1; }
    out=$(sing-box check -c "$4" 2>&1) ||
        { echo "ERR:sing-box: $(printf '%s' "$out" | sed 's/\x1b\[[0-9;]*m//g' | tail -n 1)"; return 1; }
}

# Root: the rule-sets routing $1 needs, from the calling user's download
# dir $2 (owned by them, no symlinks: routing.py install-rules) to
# $rules_etc. Ones no longer needed stay until prune_rules (a rollback may
# need them).
install_rules() {
    python3 -I "$here/routing.py" install-rules "$1" "${2:-}" "$rules_etc" "${PKEXEC_UID:--1}"
}

# Root: drop the rule-sets routing $1 does not need (the new config is up).
prune_rules() {
    python3 -I "$here/routing.py" prune-rules "$1" "$rules_etc"
}

# Root: restart the running unit on the just-installed $config and make sure
# it stays up: what `check` cannot see fails only at start. $1 = Xray with
# it: "on" (restart on the new $xray_config), "off" (stop), "" (untouched).
# If it does not come up, roll_back (the view still describes the .bak
# copies: it is written only after this). A unit that is not
# running (stopped, failed, crash-looping: maybe not the config's fault,
# e.g. another VPN holds the routes) is not started here: $unchecked is set,
# the change is in place for the next start, unverified (an UNCHECKED line
# tells the panel). A running Xray still follows its new config.
restart_checked() {
    local xr=${1:-} xu=""
    [ "$xr" = on ] && xu=xray
    if ! systemctl is-active -q "$unit"; then
        case $xr in
        on)
            # A running (or starting) Xray is checked on its new config: if
            # it does not stay up, the configs go back (the sing-box one
            # names its ports / keys).
            case $(systemctl is-active xray 2>/dev/null) in
            inactive | failed) ;;
            *)
                systemctl restart xray
                stays_up xray || roll_back xray on
                ;;
            esac
            ;;
        off) systemctl stop xray ;;
        esac
        unchecked=1
        echo "UNCHECKED:sing-box is not running: applies on its next start"
        return 0
    fi
    case $xr in
    on) systemctl restart xray ;;
    off) systemctl stop xray ;;
    esac
    # shellcheck disable=SC2086 # $xu: none or one word
    systemctl restart "$unit" && stays_up "$unit" $xu && return 0
    roll_back "$unit" "$xr"
}

# Root: $1 (sing-box or xray) did not come up on the new configs ($2 = Xray
# as for restart_checked). The .bak copies go back ($base's too with
# $with_base), what ran before runs again and is checked the same way, and
# this fails, saying how that went. A config without a .bak (none before)
# is not run again: sing-box is stopped instead of left failing.
roll_back() {
    local what=$1 xr=${2:-} name=sing-box why restored="" xrestored="" up=()
    [ "$what" = xray ] && name=Xray
    why=$(journalctl -u "$what" ${xr:+-u xray} -n 20 -o cat --since "-10s" 2>/dev/null | grep -iE 'fatal|error' |
        tail -n 1 | sed 's/\x1b\[[0-9;]*m//g')
    if [ -f "$config.bak" ]; then
        install -m 640 -g "$unit" "$config.bak" "$config"
        restored=1
    fi
    [ -n "${with_base:-}" ] && [ -f "$base.bak" ] && install -m 600 "$base.bak" "$base"
    if [ "$xr" = on ] && [ -f "$xray_config.bak" ]; then
        install -m 640 -g xray "$xray_config.bak" "$xray_config"
        xrestored=1
    fi
    if [ "$what" = "$unit" ] && [ -z "$restored" ]; then
        [ -n "$xr" ] && systemctl stop xray
        systemctl stop "$unit"
        err "sing-box did not start with it (no previous config to restore)${why:+: $why}$(ks_note)"
    fi
    # Xray, if this touched it: on its old config if the old setup uses it,
    # else stopped.
    if [ -n "$xr" ]; then
        if uses_xray && { [ "$xr" = off ] || [ -n "$xrestored" ]; }; then
            systemctl restart xray
            up+=(xray)
        else
            systemctl stop xray
        fi
    fi
    if [ "$what" = "$unit" ]; then
        systemctl restart "$unit"
        up=("$unit" "${up[@]}")
    fi
    [ ${#up[@]} -gt 0 ] && ! stays_up "${up[@]}" &&
        err "$name did not start with it, nor with the previous config${why:+: $why}$(ks_note)"
    [ "$what" = xray ] && [ -z "$xrestored" ] &&
        err "Xray did not start with it (no previous config to restore: stopped)${why:+: $why}"
    # Xray left alone (not this change's) may be down all the same.
    [ -z "$xr" ] && uses_xray && [ "$(xray_state)" = down ] &&
        err "$name did not start with it, previous config restored (but Xray is down or restarting after a crash: its nodes do not work now)${why:+: $why}"
    err "$name did not start with it, previous config restored${why:+: $why}"
}

# Root: the units $@ come up and stay up for a second; any failed / stopped
# one ends the wait early, ~6 s at most.
stays_up() {
    local i u s n=0
    for i in $(seq 30); do
        sleep 0.2
        s=active
        for u in "$@"; do
            case $(systemctl is-active "$u" 2>/dev/null) in
            active) ;;
            failed | inactive) return 1 ;;
            *) s=starting ;;
            esac
        done
        if [ "$s" = active ]; then
            n=$((n + 1))
            [ $n -ge 5 ] && return 0
        else
            n=0
        fi
    done
    return 1
}

# Root halves that change configs run one at a time: an exclusive lock on
# $restart_mark, taken before their .bak copies (a second one would
# overwrite the first's rollback). `state` reads it as restarting. 30 s at
# most: the file is world-readable, anyone can hold a shared lock on it.
lock_ops() {
    mkdir -p -m 755 "$(dirname "$restart_mark")" || err "cannot create $(dirname "$restart_mark")"
    exec 9>>"$restart_mark" && chmod 644 "$restart_mark" || err "cannot open $restart_mark"
    flock -w 30 9 || err "another VPN operation is still running"
}

# Xray: up | starting | down (failed, stopped, or waiting out Restart= after
# a crash, which is "activating" too: auto-restart, auto-restart-queued in
# systemd 254+).
xray_state() {
    case $(systemctl is-active xray 2>/dev/null) in
    active) echo up ;;
    activating | reloading)
        case $(systemctl show -P SubState xray 2>/dev/null) in
        auto-restart*) echo down ;;
        *) echo starting ;;
        esac
        ;;
    *) echo down ;;
    esac
}

# Root: a note for an error that leaves sing-box down while the kill switch
# holds traffic.
ks_note() {
    systemctl is-active -q "$ks_unit" && echo "; the kill switch blocks traffic until VPN stop"
}

# User: download the rule-sets routing $1 needs to $rules_cache (each from
# the first source that has it); ones younger than a day are kept unless $2.
fetch_rules() {
    local list line f u got
    list=$(python3 -I "$here/routing.py" rulesets "$1") || err "${list#ERR:}"
    [ -n "$list" ] || return 0
    mkdir -p "$rules_cache"
    while IFS= read -r line; do
        IFS=$'\t' read -r -a parts <<<"$line"
        f=${parts[0]}
        [ -z "${2:-}" ] && [ -n "$(find "$rules_cache/$f" -mmin -1440 2>/dev/null)" ] && continue
        got=""
        for u in "${parts[@]:1}"; do
            if curl -4 -sfL --connect-timeout 10 -m 120 "$u" -o "$rules_cache/$f.part" &&
                [ "$(head -c3 "$rules_cache/$f.part")" = SRS ]; then
                mv "$rules_cache/$f.part" "$rules_cache/$f"
                got=1
                break
            fi
        done
        rm -f "$rules_cache/$f.part"
        # A stale copy beats none (GitHub unreachable right now): ours, or
        # root's installed one (install_rules keeps it when we have none).
        [ -n "$got" ] || [ -s "$rules_cache/$f" ] || [ -s "$rules_etc/$f" ] || err "cannot download ${f%.srs}"
    done <<<"$list"
}

# Root: rewrite the view from $config. $1 = the Xray node list of a fresh
# apply; without one the current view's is kept (a node switch).
write_view() {
    local nodes=${1:-} own="" tmp
    if [ -z "$nodes" ] && [ -r "$view" ]; then
        own=$(mktemp) || return 1
        # (A view from before base / xray existed: parse the shown type.)
        jq -r '.profiles[] | select(.xray // (.type | endswith(" · xray")))
            | "\(.tag)\t\(.base // (.type | rtrimstr(" · xray")))\t\(if .insecure then "insecure" else "" end)"' "$view" >"$own"
        nodes=$own
    fi
    tmp=$(mktemp) || return 1
    local ok=0
    view_of "$nodes" >"$tmp" && mkdir -p "$(dirname "$view")" && install -m 644 "$tmp" "$view" || ok=1
    rm -f "$tmp" $own
    return $ok
}

# Root: the polkit rule for user $1 (see `setup`).
write_rule() {
    mkdir -p "$(dirname "$rule")"
    cat >"$rule" <<EOF
// Flicker VPN card (scripts/vpn/vpn.sh setup): ${1} may, from the active
// local session and without a password, start / stop ${unit}.service,
// xray.service and ${ks_unit}.service, and run the root-owned
// ${sys_dir}/vpn.sh for a node switch (_select) or a routing-only apply
// (_reroute; the overlay stays root's applied copy).
polkit.addRule(function (action, subject) {
    if (subject.user != "${1}" || !subject.local || !subject.active)
        return polkit.Result.NOT_HANDLED;
    if (action.id == "org.freedesktop.systemd1.manage-units" &&
        ["${unit}.service", "xray.service", "${ks_unit}.service"].indexOf(action.lookup("unit")) >= 0 &&
        ["start", "stop", "restart", "try-restart"].indexOf(action.lookup("verb")) >= 0)
        return polkit.Result.YES;
    if (action.id == "org.freedesktop.policykit.exec" &&
        action.lookup("program") == "${sys_dir}/vpn.sh" &&
        /^\S+ (_select|_reroute) /.test(action.lookup("command_line") || ""))
        return polkit.Result.YES;
    return polkit.Result.NOT_HANDLED;
});
EOF
    chmod 644 "$rule"
}

# Root: the kill switch's ruleset — output only (this host's own traffic).
# The VPN's own paths first, then the LAN minus DNS (the router would
# forward the names to the ISP), then reject (fails fast instead of hanging).
# `ct status dnat`: sing-box's auto_redirect sends TCP to its local port in
# the nat output hook, and the filter hook still sees the pre-NAT interface.
# Into $1 (install_ks_rules puts it in place).
write_ks_rules() {
    local uids out=$1
    uids=$(id -u "$unit") || return 1
    id -u xray >/dev/null 2>&1 && uids="$uids, $(id -u xray)"
    cat >"$out" <<EOF
# Flicker VPN kill switch (scripts/vpn/vpn.sh), loaded by ${ks_unit}.service.
table ${ks_table}
delete table ${ks_table}
table ${ks_table} {
    chain output {
        type filter hook output priority filter; policy accept;
        oifname "lo" accept
        oifname "${tun_name}" accept
        meta skuid { ${uids} } accept
        ct status dnat accept
        meta l4proto { tcp, udp } th dport { 53, 853 } reject
        ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 224.0.0.0/4, 255.255.255.255 } accept
        ip6 daddr { fe80::/10, ff00::/8 } accept
        meta l4proto tcp reject with tcp reset
        reject with icmpx admin-prohibited
    }
}
EOF
    chmod 644 "$out"
}

ks_on() { [ -e "$ks_dropin" ]; }

# Root: while the kill switch is on, rewrite its table (the uids it lets
# through: Xray may have been installed since it was turned on) and reload
# it if it is up (the file deletes the old table first).
refresh_ks() {
    ks_on || return 0
    install_ks_rules || return 1
    if systemctl is-active -q "$ks_unit"; then nft -f "$ks_rules"; fi
}

# Root: write the kill switch's table to $ks_rules only once `nft -c` takes
# it: the unit loads that file, a broken one would leave the VPN unguarded.
install_ks_rules() {
    local tmp rc
    tmp=$(mktemp) || return 1
    write_ks_rules "$tmp" && nft -c -f "$tmp" && install -D -m 644 "$tmp" "$ks_rules"
    rc=$?
    rm -f "$tmp"
    return $rc
}

# Root: name the TUN of config file $1 $tun_name if it is not yet (one from
# before the TUN had a fixed name): the kill switch lets only that interface
# through. The rest = `install` args for it. 0 = renamed, 1 = nothing to
# do (named already, or no such file), 2 = the rename failed.
name_tun() {
    local f=$1 tmp rc
    shift
    [ -r "$f" ] || return 1
    jq -e --arg n "$tun_name" '[.inbounds[]? | select(.type == "tun")] | all(.interface_name == $n)' "$f" >/dev/null &&
        return 1
    tmp=$(mktemp) || return 2
    jq --arg n "$tun_name" '(.inbounds[]? | select(.type == "tun") | .interface_name) = $n' "$f" >"$tmp" &&
        sing-box check -c "$tmp" && install "$@" "$tmp" "$f"
    rc=$?
    rm -f "$tmp"
    [ $rc -eq 0 ] || return 2
}

# Root: keep a copy of $1 as $1.bak for a rollback (0600: the same secrets);
# none (no $1) = no stale .bak either.
backup() {
    if [ -f "$1" ]; then install -m 600 "$1" "$1.bak"; else rm -f "$1.bak"; fi
}

# Tag of the first selector outbound (empty = none).
selector() {
    jq -r '[.outbounds[]? | select(.type == "selector") | .tag][0] // empty' "$config" 2>/dev/null
}

# These go through pkexec: without it its exec fails with 127, which the
# panel would show as "not authorized".
case "${1:-}" in
killswitch | select | subscribe | update | apply)
    command -v pkexec >/dev/null || err "pkexec (polkit) is not installed"
    ;;
esac

case "${1:-}" in
state)
    installed=false
    command -v sing-box >/dev/null && installed=true
    # Before and after the units are read: a restart that starts or ends
    # in between still counts. Locked = a root half is restarting (a shared
    # lock needs only read access; 1 = held, anything else = no).
    restarting=false
    marked() {
        { flock -n -s 9; [ $? -eq 1 ]; } 9<"$restart_mark"
    } 2>/dev/null
    marked && restarting=true
    st=$(systemctl is-active "$unit" 2>/dev/null)
    # Up only once both are. Xray down (xray_state) = only its nodes are:
    # the probe through the active one tells (offline after the stall).
    if [ "$st" = active ] && uses_xray && [ "$(xray_state)" = starting ]; then
        st=activating
    fi
    enabled=false
    [ "$(systemctl is-enabled "$unit" 2>/dev/null)" = enabled ] && enabled=true
    online=false
    # IPv6 is broken on some hosts: -4.
    if [ "$st" = active ] && curl -4 -s -o /dev/null --connect-timeout 1 -m 2 "$probe"; then
        online=true
    fi
    sub=false
    [ -s "$sub_file" ] && sub=true
    ks=false
    ks_on && ks=true
    # Traffic held back: the table is up and sing-box is not (crashed,
    # failed, stopped behind Flicker's back).
    blocking=false
    if systemctl is-active -q "$ks_unit" && ! systemctl is-active -q "$unit"; then
        blocking=true
    fi
    marked && restarting=true
    # The view; an install from before it existed: the config, if readable.
    v=""
    if [ -r "$view" ]; then
        v=$(cat "$view")
    elif [ -r "$config" ]; then
        v=$(view_of "$legacy_nodes")
    fi
    jq -nc --argjson v "${v:-{\}}" --arg unit "$st" --argjson enabled "$enabled" --argjson installed "$installed" \
        --argjson online "$online" --argjson sub "$sub" --argjson ks "$ks" --argjson blocking "$blocking" \
        --argjson restarting "$restarting" --arg ch "$(hash_of "$custom_file")" \
        '{ installed: $installed, unit: $unit, enabled: $enabled, online: $online, subscription: $sub,
        killswitch: $ks, blocking: $blocking, restarting: $restarting,
        profile: ($v.profile // ""), profiles: ($v.profiles // []),
        routing: ($v.routing // {}), customPending: ($ch != ($v.customHash // "")) }'
    ;;
start | restart | enable | disable)
    # Xray first: sing-box's shadowsocks outbounds point at it. The kill
    # switch (if on) comes up with sing-box by itself (its drop-in).
    if uses_xray; then
        systemctl "$1" xray "$unit" || err "systemctl $1 failed"
    else
        systemctl "$1" "$unit" || err "systemctl $1 failed"
    fi
    ;;
stop)
    # Stop Xray too even if no node needs it any more. A deliberate stop is
    # the one thing that lowers the kill switch (also after a crash).
    units=("$unit")
    # Also one waiting out Restart= after a crash (shown as activating).
    case $(systemctl is-active xray 2>/dev/null) in
    inactive | failed) ;;
    *) units+=(xray) ;;
    esac
    systemctl is-active -q "$ks_unit" && units+=("$ks_unit")
    systemctl stop "${units[@]}" || err "systemctl stop failed"
    ;;
killswitch)
    case "${2:-}" in
    on | off) ;;
    *) err "usage: killswitch on|off" ;;
    esac
    exec pkexec "$(root_self)" _killswitch "$2" "$(id -un)"
    ;;
select)
    [ -n "${2:-}" ] || err "usage: select <tag>"
    exec pkexec "$(root_self)" _select "$2"
    ;;
subscribe)
    url=${2:-}
    case "$url" in
    http://* | https://*) ;;
    *) err "not an http(s) URL" ;;
    esac
    mkdir -p "$state_dir"
    (umask 077 && printf '%s' "$url" >"$sub_file")
    raw=$(mktemp) || err "mktemp"
    trap 'rm -f "$raw"' EXIT
    curl -4 -sfL -m 20 -A sing-box "$url" -o "$raw" || err "download failed"
    [ -s "$raw" ] || err "empty subscription"
    # The applied routing's rule-sets, refreshed along with the nodes.
    [ -s "$routing_etc" ] && fetch_rules "$routing_etc"
    pkexec "$(root_self)" _apply "$raw" "$rules_cache"
    ;;
apply)
    mkdir -p "$state_dir"
    [ -n "${2:-}" ] && printf '%s\n' "$2" >"$routing_file"
    [ -s "$routing_file" ] || echo '{}' >"$routing_file"
    out=$(python3 -I "$here/routing.py" check "$routing_file" "$custom_file") || err "${out#ERR:}"
    fetch_rules "$routing_file" "${3:-}"
    # The overlay as applied (the view's hash of root's copy): routing only,
    # password-free with `setup` done; a changed overlay always asks.
    if [ "$(hash_of "$custom_file")" = "$(jq -r '.customHash // ""' "$view" 2>/dev/null)" ]; then
        exec pkexec "$(root_self)" _reroute "$(cat "$routing_file")" "$rules_cache"
    fi
    exec pkexec "$(root_self)" _routing "$(cat "$routing_file")" "$custom_file" "$rules_cache"
    ;;
edit)
    if [ ! -e "$custom_file" ]; then
        mkdir -p "$(dirname "$custom_file")"
        # Merged over the generated config (routing.py): rules here go first.
        printf '%s\n' '{' '  "route": { "rules": [] },' '  "dns": { "rules": [] }' '}' >"$custom_file"
    fi
    ed=${VISUAL:-${EDITOR:-}}
    if [ -z "$ed" ]; then
        for e in nvim vim nano vi; do
            command -v "$e" >/dev/null && { ed=$e; break; }
        done
    fi
    # shellcheck disable=SC2086 # "$EDITOR" may carry flags
    exec $ed "$custom_file"
    ;;
update)
    [ -s "$sub_file" ] || err "no subscription"
    exec "$self" subscribe "$(cat "$sub_file")"
    ;;
ping)
    t=$(curl -4 -s -o /dev/null -w '%{time_total}' --connect-timeout 5 -m 6 "$probe") || err "timeout"
    echo "OK:$(awk -v t="$t" 'BEGIN { printf "%d", t * 1000 }')"
    ;;
speedtest)
    command -v speedtest-cli >/dev/null || { echo ERR_MISSING; exit 1; }
    speedtest-cli --simple 2>/dev/null || { echo ERR_FAILED; exit 1; }
    ;;
setup)
    [ "$(id -u)" -eq 0 ] || exec pkexec "$self" setup "$(id -un)"
    install -d -m 755 "$sys_dir"
    [ "$here" != "$sys_dir" ] && for f in "${sys_files[@]}"; do
        install -m 755 -o root -g root "$here/$f" "$sys_dir/$f" || err "cannot install $f"
    done
    write_rule "${2:?user}"
    echo "OK:$rule"
    ;;

# Root halves (pkexec) -------------------------------------------------------
_select)
    [ "$(id -u)" -eq 0 ] || err "root only"
    lock_ops
    ms=$(selector)
    [ -n "$ms" ] || err "no selector outbound in $config"
    jq -e --arg ms "$ms" --arg tag "$2" \
        '.outbounds[] | select(.type == "selector" and .tag == $ms) | .outbounds | index($tag) != null' \
        "$config" >/dev/null || err "no node $2"
    tmp=$(mktemp) && btmp=$(mktemp) || err "mktemp"
    trap 'rm -f "$tmp" "$btmp"' EXIT
    sel='(.outbounds[] | select(.type == "selector" and .tag == $ms) | .default) = $tag'
    jq --arg ms "$ms" --arg tag "$2" "$sel" "$config" >"$tmp" || err "jq failed"
    # The base too (first: if the config then fails, the next recompose
    # still picks the node), or the next recompose would switch back.
    backup "$config"
    if [ -f "$base" ]; then
        jq --arg ms "$ms" --arg tag "$2" "$sel" "$base" >"$btmp" || err "jq failed on $base"
        backup "$base"
        with_base=1
        install -m 600 "$btmp" "$base" || err "cannot update $base"
    fi
    if ! install -m 640 -g "$unit" "$tmp" "$config"; then
        # Or the next recompose would switch to the node after all.
        [ -n "${with_base:-}" ] && install -m 600 "$base.bak" "$base"
        err "cannot update $config"
    fi
    # The view only once it is up: a rollback keeps the old node shown.
    restart_checked
    write_view || err "view update failed"
    echo "OK:$2"
    ;;
_killswitch)
    [ "$(id -u)" -eq 0 ] || err "root only"
    lock_ops
    if [ "$2" = on ]; then
        command -v nft >/dev/null || err "nft (nftables) is not installed"
        id -u "$unit" >/dev/null 2>&1 || err "no $unit user"
        install_ks_rules || err "kill switch rules: nft rejected them or they could not be installed"
        # A config from before the TUN had a fixed name: name it, or the
        # table would block the VPN's own interface. The base too, or the
        # next recompose would bring the old name back. Before the switch
        # exists: if that fails (or sing-box does not come up with it, which
        # rolls both back), it does not go on.
        backup "$config"
        if [ -f "$base" ]; then
            backup "$base"
            with_base=1
            name_tun "$base" -m 600
            [ $? -eq 2 ] && err "cannot name the TUN $tun_name in $base"
        fi
        name_tun "$config" -m 640 -g "$unit"
        case $? in
        0) restart_checked ;;
        2)
            [ -n "${with_base:-}" ] && install -m 600 "$base.bak" "$base"
            err "cannot name the TUN $tun_name in $config"
            ;;
        esac
        cat >"$ks_unit_file" <<EOF
# Flicker VPN kill switch (scripts/vpn/vpn.sh): pulled in by ${unit}.service,
# stopped only by "vpn.sh stop" — it outlives a crashed sing-box.
[Unit]
Description=Flicker VPN kill switch
Before=${unit}.service xray.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/nft -f ${ks_rules}
ExecStop=-/usr/bin/nft delete table ${ks_table}
EOF
        mkdir -p "$(dirname "$ks_dropin")"
        printf '[Unit]\nWants=%s.service\n' "$ks_unit" >"$ks_dropin"
        # The password-free rule (if installed) learns the new unit.
        [ -e "$rule" ] && [ -n "${3:-}" ] && write_rule "$3"
        systemctl daemon-reload
        if systemctl is-active -q "$unit"; then
            systemctl start "$ks_unit" || err "kill switch failed to start"
        fi
    else
        systemctl stop "$ks_unit" 2>/dev/null
        rm -f "$ks_dropin"
        rmdir "$(dirname "$ks_dropin")" 2>/dev/null
        systemctl daemon-reload
    fi
    echo "OK:killswitch $2"
    ;;
_apply)
    [ "$(id -u)" -eq 0 ] || err "root only"
    lock_ops
    # Not *.json and not in /etc/sing-box: the unit merges every *.json there.
    tmp=$(mktemp) || err "mktemp"
    xtmp=$(mktemp) || err "mktemp"
    ntmp=$(mktemp) || err "mktemp"
    etmp=$(mktemp) || err "mktemp"
    trap 'rm -f "$tmp" "$xtmp" "$ntmp" "$etmp"' EXIT
    python3 -I "$here/sub_parser.py" "$tmp" "$2" "$etmp" || err "no nodes in the subscription"
    # Keep the chosen node across an update (the parser defaults to the first,
    # often a provider's placeholder) if the new subscription still has it.
    keep=$([ -r "$config" ] && jq -r --arg ms "$(selector)" \
        '[.outbounds[]? | select(.type == "selector" and .tag == $ms) | .default][0] // empty' "$config")
    if [ -n "$keep" ]; then
        jq --arg tag "$keep" '(.outbounds[] | select(.type == "selector" and (.outbounds | index($tag) != null)) | .default) = $tag' \
            "$tmp" >"$tmp.keep" && mv "$tmp.keep" "$tmp"
    fi
    # gRPC / XHTTP nodes to Xray (only when it is installed).
    if xuid=$(id -u xray 2>/dev/null) && command -v xray >/dev/null; then
        python3 -I "$here/xray_split.py" "$tmp" "$xtmp" "$ntmp" "$xuid" "$etmp" || err "xray split failed"
    fi
    sing-box check -c "$tmp" || err "sing-box rejected the generated config"
    # $tmp = the new base; the config = it + the applied routing / overlay.
    install_rules "$routing_etc" "${3:-}" || err "rule-set install failed"
    ctmp=$(mktemp) || err "mktemp"
    trap 'rm -f "$tmp" "$xtmp" "$ntmp" "$etmp" "$ctmp"' EXIT
    out=$(compose "$tmp" "$routing_etc" "$custom_etc" "$ctmp") || err "${out#ERR:}"
    if [ -s "$ntmp" ]; then
        # Format by extension otherwise, and mktemp names have none.
        out=$(xray run -test -format json -config "$xtmp" 2>&1) ||
            err "xray rejected the generated config: $(printf '%s' "$out" | grep -v 'Reading config' | tail -n 1)"
    fi
    mkdir -p "$(dirname "$config")"
    # Backups hold the same secrets: root only.
    # Xray's uid may be new to the kill switch: let it through before it runs.
    refresh_ks || err "kill switch update failed"
    backup "$config"
    install -m 640 -g "$unit" "$ctmp" "$config"
    xr=off
    if [ -s "$ntmp" ]; then
        xr=on
        mkdir -p "$(dirname "$xray_config")"
        backup "$xray_config"
        install -m 640 -g xray "$xtmp" "$xray_config"
    fi
    # Base and view only once it is up: a rollback keeps the old ones.
    restart_checked "$xr"
    mkdir -p "$(dirname "$base")"
    install -m 600 "$tmp" "$base"
    write_view "$ntmp" || err "view update failed"
    rm -f "$legacy_nodes"
    # Unverified (not running): the old rule-sets stay for a rollback by hand.
    [ -n "$unchecked" ] || prune_rules "$routing_etc"
    echo "OK:applied"
    ;;
_routing | _reroute)
    [ "$(id -u)" -eq 0 ] || err "root only"
    lock_ops
    # $2 the routing (JSON text, not a path: a password-free caller could
    # name a root-only file, which would end up 0644 in $routing_etc).
    # _routing (polkit asks): $3 the user's overlay (may be missing), $4 the
    # rule-set downloads. _reroute (password-free): $3 the downloads; the
    # overlay is the applied one, untouched.
    tmps=()
    trap 'rm -f "${tmps[@]}"' EXIT
    rtmp=$(mktemp) && otmp=$(mktemp) && ctmp=$(mktemp) || err "mktemp"
    tmps=("$rtmp" "$otmp" "$ctmp")
    printf '%s\n' "${2:-}" >"$rtmp"
    if [ "$1" = _routing ]; then
        dl=${4:-}
        [ ! -L "${3:-}" ] || err "$3 is a symlink"
        if [ -f "${3:-}" ]; then cat -- "$3" >"$otmp" || err "cannot read $3"; else otmp=""; fi
    else
        dl=${3:-}
        if [ -f "$custom_etc" ]; then cat "$custom_etc" >"$otmp"; else otmp=""; fi
    fi
    out=$(python3 -I "$here/routing.py" check "$rtmp" "$otmp") || err "${out#ERR:}"
    # Before the base existed the config was one (nothing composed in yet).
    b=$base
    [ -f "$b" ] || b=$config
    [ -f "$b" ] || err "no config yet: import a subscription first"
    # A base from before the TUN had a fixed name (the kill switch needs it).
    if [ -f "$base" ]; then
        name_tun "$base" -m 600
        [ $? -eq 2 ] && err "cannot name the TUN $tun_name in $base"
    fi
    install_rules "$rtmp" "$dl" || err "rule-set install failed"
    out=$(compose "$b" "$rtmp" "$otmp" "$ctmp") || err "${out#ERR:}"
    mkdir -p "$(dirname "$base")"
    [ -f "$base" ] || install -m 600 "$config" "$base"
    backup "$config"
    install -m 640 -g "$unit" "$ctmp" "$config"
    # If it does not come up, the copies below stay the old ones, so the
    # change is still pending.
    restart_checked
    install -m 644 "$rtmp" "$routing_etc"
    [ -n "$unchecked" ] || prune_rules "$rtmp"
    # The overlay may name its own servers / keys: root only.
    if [ "$1" = _routing ]; then
        if [ -n "$otmp" ]; then install -m 600 "$otmp" "$custom_etc"; else rm -f "$custom_etc"; fi
    fi
    write_view || err "view update failed"
    echo "OK:routing applied"
    ;;
*)
    sed -n '2,/^set -u$/{/^set -u$/!p}' "$self"
    exit 2
    ;;
esac
