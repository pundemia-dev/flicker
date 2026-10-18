#!/usr/bin/env python3
# Moves the nodes sing-box cannot carry to Xray (scripts/vpn/vpn.sh _apply).
#
# sing-box stays the TUN / routing / DNS engine. Its gRPC transport is the
# "lite" one unless built with_grpc (Arch's is not), which Xray servers
# reject; XHTTP it has no transport for at all. Each such node becomes an
# Xray outbound behind its own local shadowsocks-2022 inbound (127.0.0.1,
# a random free port), and the sing-box outbound of the same tag a
# `shadowsocks` client to it — the selector, the node list and switching do
# not change. Xray's own uplink
# connections must not enter the TUN again: its uid is excluded from the
# TUN routes (tun.exclude_uid) and, should one still get in, routed direct
# (route rule `user`). The local hops are keyed (a fresh random key per node
# each run): other local programs cannot ride the tunnel through them. Not
# SOCKS: its password covers TCP only, UDP ASSOCIATE datagrams carry no auth;
# shadowsocks-2022 authenticates every packet, UDP included.
#
# Argv: <sing-box config (rewritten in place)> <xray config out>
#       <nodes out: "tag<TAB>type<TAB>flags" per moved node> <xray uid>
#       [extras (sub_parser.py's Xray-only link parameters)]
# flags: "insecure" = the link asked to skip the certificate check, which
# Xray no longer can (allowInsecure was removed in 2026-06): it verifies.
# Exit 0 = written (no moved node → empty nodes file, no Xray config);
# 1 = bad input.

import base64
import json
import secrets
import socket
import sys

XRAY_TRANSPORTS = ("grpc", "xhttp")
XRAY_PROTOCOLS = ("vless", "vmess", "trojan")
SS_METHOD = "2022-blake3-aes-128-gcm"  # key = 16 random bytes, base64
PORT_RANGE = (20000, 60000)


def warn(msg):
    sys.stderr.write("xray_split: %s\n" % msg)


def free_port(taken):
    """A random port in PORT_RANGE free on 127.0.0.1 for both TCP and UDP."""
    for _ in range(200):
        port = PORT_RANGE[0] + secrets.randbelow(PORT_RANGE[1] - PORT_RANGE[0])
        if port in taken:
            continue
        try:
            for kind in (socket.SOCK_STREAM, socket.SOCK_DGRAM):
                with socket.socket(socket.AF_INET, kind) as s:
                    s.bind(("127.0.0.1", port))
        except OSError:
            continue
        taken.add(port)
        return port
    raise OSError("no free local port")


def stream(ob, extra):
    tr = ob.get("transport") or {}
    tls = ob.get("tls") or {}
    s = {"network": tr["type"]}
    if tr["type"] == "grpc":
        g = {"serviceName": tr.get("service_name", "")}
        if extra.get("authority"):
            g["authority"] = extra["authority"]
        if extra.get("multiMode"):
            g["multiMode"] = True
        s["grpcSettings"] = g
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
        if extra.get("spiderX"):
            r["spiderX"] = extra["spiderX"]
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


def outbound(ob, tag, extra):
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
    return {"tag": tag, "protocol": t, "settings": settings, "streamSettings": stream(ob, extra)}


def main():
    if len(sys.argv) < 5:
        sys.exit(1)
    sb_path, xray_path, nodes_path, uid = sys.argv[1:5]
    extras_path = sys.argv[5] if len(sys.argv) > 5 else ""
    try:
        with open(sb_path, encoding="utf-8") as f:
            cfg = json.load(f)
        uid = int(uid)
        extras = {}
        if extras_path:
            with open(extras_path, encoding="utf-8") as f:
                extras = json.load(f)
    except Exception as e:
        warn(str(e))
        sys.exit(1)

    inbounds, outbounds, rules, nodes = [], [], [], []
    ports = set()
    for ob in cfg.get("outbounds", []):
        tr = (ob.get("transport") or {}).get("type")
        if tr not in XRAY_TRANSPORTS or ob.get("type") not in XRAY_PROTOCOLS:
            continue
        i = len(nodes)
        try:
            outbounds.append(outbound(ob, "out-%d" % i, extras.get(ob.get("tag"), {})))
        except KeyError as e:
            warn("%s: missing %s, left to sing-box" % (ob.get("tag"), e))
            continue
        try:
            port = free_port(ports)
        except OSError as e:
            warn(str(e))
            sys.exit(1)
        key = base64.b64encode(secrets.token_bytes(16)).decode()
        inbounds.append({"tag": "in-%d" % i, "listen": "127.0.0.1", "port": port,
                         "protocol": "shadowsocks",
                         "settings": {"method": SS_METHOD, "password": key,
                                      "network": "tcp,udp"}})
        rules.append({"inboundTag": ["in-%d" % i], "outboundTag": "out-%d" % i})
        insecure = bool((ob.get("tls") or {}).get("insecure"))
        nodes.append((ob["tag"], ob["type"], "insecure" if insecure else ""))
        tag = ob["tag"]
        ob.clear()
        ob.update({"type": "shadowsocks", "tag": tag, "server": "127.0.0.1",
                   "server_port": port, "method": SS_METHOD, "password": key})

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
        for tag, t, flags in nodes:
            f.write("%s\t%s\t%s\n" % (tag, t, flags))
    sys.stderr.write("xray_split: %d node(s) to Xray\n" % len(nodes))


if __name__ == "__main__":
    main()
