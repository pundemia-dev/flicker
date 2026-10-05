#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
#
# LocalSend discovery: UDP multicast announce/listen + HTTP subnet fallback scan.
# Runs across EVERY local IPv4 interface (not just the one the default route
# picks) so it keeps working when a VPN tunnel captures the multicast route.
# Emits one `alias\tip\tdeviceType\tdeviceModel` per discovered device, then exits.

import socket, json, time, struct, re, subprocess, asyncio, ssl, ipaddress

MCAST = '224.0.0.167'
PORT  = 53317
ANNOUNCE_ALIAS = "pillShell Stash"
FINGERPRINT = "pillshell_stash_discover"

# Enumerate every IPv4 interface (name, ip, prefixlen). A VPN makes the
# kernel's multicast route point at the tunnel, so we can't trust a single
# route lookup — we act on all of them and let unreachable ones fail quietly.
out = subprocess.check_output(["ip", "-4", "-o", "addr", "show"], text=True)
local_ips = set()
ifaces = []  # [(name, ip, prefixlen)]
for line in out.splitlines():
    m = re.match(r'\d+:\s+(\S+)\s+inet\s+(\d+\.\d+\.\d+\.\d+)/(\d+)', line)
    if not m:
        continue
    name, ip, plen = m.group(1), m.group(2), int(m.group(3))
    local_ips.add(ip)
    if name == 'lo' or ip.startswith('127.'):
        continue
    ifaces.append((name, ip, plen))

def is_private(ip):
    try:
        return ipaddress.ip_address(ip).is_private
    except ValueError:
        return False

seen = set()
def emit(ip, info):
    if ip in seen or ip in local_ips:
        return
    seen.add(ip)
    alias = (info.get('alias') or 'Unknown').replace('\t', ' ')
    dtype = (info.get('deviceType') or '').replace('\t', ' ')
    dmodel = (info.get('deviceModel') or '').replace('\t', ' ')
    print(f"{alias}\t{ip}\t{dtype}\t{dmodel}", flush=True)

announce = json.dumps({
    "alias": ANNOUNCE_ALIAS, "version": "2.1",
    "deviceModel": None, "deviceType": "headless",
    "fingerprint": FINGERPRINT,
    "port": PORT, "protocol": "https",
    "download": False, "announce": True
}).encode()

# Phase 1: UDP multicast announce + listen on ALL interfaces.
rx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
rx.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
rx.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
rx.bind(('', PORT))
# Join the group on each interface (one socket can hold many memberships),
# plus a wildcard join as a last-resort fallback.
for _name, ip, _plen in ifaces:
    try:
        rx.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP,
                      struct.pack('4s4s', socket.inet_aton(MCAST), socket.inet_aton(ip)))
    except OSError:
        pass
try:
    rx.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP,
                  struct.pack('4sL', socket.inet_aton(MCAST), socket.INADDR_ANY))
except OSError:
    pass
rx.settimeout(0.1)

tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
tx.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 4)

def send_announce():
    for _name, ip, _plen in ifaces:
        try:
            tx.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton(ip))
            tx.sendto(announce, (MCAST, PORT))
        except OSError:
            pass

send_announce()
deadline = time.time() + 2.0
sent_second = False
while time.time() < deadline:
    if not sent_second and time.time() > deadline - 1.0:
        send_announce()
        sent_second = True
    try:
        data, (ip, _) = rx.recvfrom(65536)
        if ip in local_ips:
            continue
        try:
            info = json.loads(data.decode())
        except Exception:
            continue
        if info.get('fingerprint') == FINGERPRINT:
            continue
        emit(ip, info)
    except socket.timeout:
        pass

# Phase 2: parallel HTTPS probe over each private interface's subnet.
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

# Collect target hosts from every private-range interface. Cap each interface
# to a /24 so a wide VPN prefix (e.g. /16) doesn't explode into 65k probes.
targets = set()
for _name, ip, plen in ifaces:
    if not is_private(ip):
        continue
    net = ipaddress.ip_network(f"{ip}/{plen}", strict=False)
    if net.num_addresses > 256:
        net = ipaddress.ip_network(f"{ip}/24", strict=False)
    for host in net.hosts():
        targets.add(str(host))
targets -= local_ips

sem = asyncio.Semaphore(256)

async def probe(ip):
    if ip in seen:
        return
    async with sem:
        try:
            r, w = await asyncio.wait_for(
                asyncio.open_connection(ip, PORT, ssl=ctx), timeout=0.6)
            w.write(f"GET /api/localsend/v2/info HTTP/1.0\r\nHost: {ip}\r\nConnection: close\r\n\r\n".encode())
            await w.drain()
            data = await asyncio.wait_for(r.read(4096), timeout=0.6)
            w.close()
            body = data.split(b'\r\n\r\n', 1)
            if len(body) < 2:
                return
            info = json.loads(body[1].decode())
            emit(ip, info)
        except Exception:
            pass

async def scan():
    await asyncio.gather(*(probe(ip) for ip in targets))

if targets:
    asyncio.run(scan())
