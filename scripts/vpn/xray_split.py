#!/usr/bin/env python3
# Moves the nodes sing-box cannot carry to Xray (scripts/vpn/vpn.sh _apply).
#
# sing-box stays the TUN / routing / DNS engine. Its gRPC transport is the
# "lite" one unless built with_grpc (Arch's is not), which Xray servers
# reject; XHTTP it has no transport for at all. Each such node becomes an
# Xray outbound behind its own local SOCKS inbound (127.0.0.1:<base + i>),
# and the sing-box outbound of the same tag a `socks` client to it — the
# selector, the node list and switching do not change. Xray's own uplink
# connections must not enter the TUN again: its uid is excluded from the
# TUN routes (tun.exclude_uid) and, should one still get in, routed direct
# (route rule `user`). The local SOCKS ports take a user / password (fresh
# random each run): other local programs cannot ride the tunnel through them.
#
# Argv: <sing-box config (rewritten in place)> <xray config out>
#       <nodes out: "tag<TAB>type" per moved node> <xray uid> [base port]
# Exit 0 = written (no moved node → empty nodes file, no Xray config);
# 1 = bad input.

import json
import secrets
import sys

XRAY_TRANSPORTS = ("grpc", "xhttp")
XRAY_PROTOCOLS = ("vless", "vmess", "trojan")


def warn(msg):
    sys.stderr.write("xray_split: %s\n" % msg)


def stream(ob):
    tr = ob.get("transport") or {}
    tls = ob.get("tls") or {}
    s = {"network": tr["type"]}
    if tr["type"] == "grpc":
        s["grpcSettings"] = {"serviceName": tr.get("service_name", "")}
    else:
        x = {}
        if tr.get("path"):
            x["path"] = tr["path"]
        host = tr.get("host")
        if host:
            x["host"] = host[0] if isinstance(host, list) else host
        if tr.get("mode"):
            x["mode"] = tr["mode"]
        s["xhttpSettings"] = x
    if not tls.get("enabled"):
        s["security"] = "none"
        return s
    fp = (tls.get("utls") or {}).get("fingerprint", "")
    reality = tls.get("reality") or {}
    if reality.get("enabled"):
        s["security"] = "reality"
        r = {
            "serverName": tls.get("server_name", ""),
            "fingerprint": fp or "chrome",
            "publicKey": reality.get("public_key", ""),
            "shortId": reality.get("short_id", ""),
        }
        s["realitySettings"] = r
        return s
    s["security"] = "tls"
    t = {}
    if tls.get("server_name"):
        t["serverName"] = tls["server_name"]
    if tls.get("alpn"):
        t["alpn"] = tls["alpn"]
    if fp:
        t["fingerprint"] = fp
    if tls.get("insecure"):
        # Xray removed allowInsecure (2026-06): the node verifies the cert.
        warn("%s: insecure TLS is not supported by Xray, verifying" % ob["tag"])
    s["tlsSettings"] = t
    return s


def outbound(ob, tag):
    t = ob["type"]
    addr, port = ob["server"], ob["server_port"]
    if t == "vless":
        settings = {"address": addr, "port": port, "id": ob["uuid"], "encryption": "none"}
        if ob.get("flow"):
            settings["flow"] = ob["flow"]
    elif t == "vmess":
        settings = {"address": addr, "port": port, "id": ob["uuid"],
                    "security": ob.get("security", "auto")}
    else:
        settings = {"address": addr, "port": port, "password": ob["password"]}
    return {"tag": tag, "protocol": t, "settings": settings, "streamSettings": stream(ob)}


def main():
    if len(sys.argv) < 5:
        sys.exit(1)
    sb_path, xray_path, nodes_path, uid = sys.argv[1:5]
    base = int(sys.argv[5]) if len(sys.argv) > 5 else 20801
    try:
        with open(sb_path, encoding="utf-8") as f:
            cfg = json.load(f)
        uid = int(uid)
    except Exception as e:
        warn(str(e))
        sys.exit(1)

    inbounds, outbounds, rules, nodes = [], [], [], []
    user, password = "flicker", secrets.token_urlsafe(24)
    for ob in cfg.get("outbounds", []):
        tr = (ob.get("transport") or {}).get("type")
        if tr not in XRAY_TRANSPORTS or ob.get("type") not in XRAY_PROTOCOLS:
            continue
        i = len(nodes)
        port = base + i
        try:
            outbounds.append(outbound(ob, "out-%d" % i))
        except KeyError as e:
            warn("%s: missing %s, left to sing-box" % (ob.get("tag"), e))
            continue
        inbounds.append({"tag": "in-%d" % i, "listen": "127.0.0.1", "port": port,
                         "protocol": "socks",
                         "settings": {"auth": "password", "udp": True, "ip": "127.0.0.1",
                                      "accounts": [{"user": user, "pass": password}]}})
        rules.append({"inboundTag": ["in-%d" % i], "outboundTag": "out-%d" % i})
        nodes.append((ob["tag"], ob["type"]))
        tag = ob["tag"]
        ob.clear()
        ob.update({"type": "socks", "tag": tag, "server": "127.0.0.1",
                   "server_port": port, "version": "5",
                   "username": user, "password": password})

    if nodes:
        for inb in cfg.get("inbounds", []):
            if inb.get("type") == "tun":
                inb["exclude_uid"] = sorted(set(inb.get("exclude_uid", []) + [uid]))
        route = cfg.setdefault("route", {})
        # After the sniff / hijack-dns rules, before anything else routes.
        route.setdefault("rules", []).append({"user_id": [uid], "outbound": "direct"})
        xray = {
            "log": {"loglevel": "warning"},
            "inbounds": inbounds,
            "outbounds": outbounds + [{"tag": "block", "protocol": "blackhole"}],
            "routing": {"rules": rules},
        }
        with open(xray_path, "w", encoding="utf-8") as f:
            json.dump(xray, f, indent=2, ensure_ascii=False)

    with open(sb_path, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
    with open(nodes_path, "w", encoding="utf-8") as f:
        for tag, t in nodes:
            f.write("%s\t%s\n" % (tag, t))
    sys.stderr.write("xray_split: %d node(s) to Xray\n" % len(nodes))


if __name__ == "__main__":
    main()
