#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
#
# LocalSend receive server for pillShell Stash.
#
# Runs as a long-lived child of the LocalSend.qml service. It does three things:
#   1. Announces itself on UDP multicast (and replies to peers' announces) so
#      other LocalSend apps list pillShell as a target.
#   2. Serves the LocalSend v2 HTTPS API on :53317.
#   3. Bridges accept/reject decisions with QML over stdin/stdout:
#        - emits one JSON object per line on stdout  (events -> QML)
#        - reads one JSON object per line on stdin    (decisions <- QML)
#
# Protocol with QML
#   stdout events:
#     {"event":"ready"}
#     {"event":"request","sessionId":..,"alias":..,"fingerprint":..,
#      "files":[{"id","name","size","type"}],"totalSize":N}
#     {"event":"progress","sessionId":..,"received":N,"total":N}
#     {"event":"file-done","sessionId":..,"name":..,"path":..}
#     {"event":"session-done","sessionId":..}
#     {"event":"cancelled","sessionId":..}
#     {"event":"timeout","sessionId":..}
#   stdin decisions:
#     {"action":"accept","sessionId":..,"dir":"/abs/path"}
#     {"action":"reject","sessionId":..}

import sys, os, json, time, struct, socket, ssl, threading, secrets, subprocess, re
import argparse, ipaddress, concurrent.futures, shutil
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib import request as urlrequest

MCAST = "224.0.0.167"
PORT = 53317
# Abandon an accepted session after this many seconds of upload inactivity
# (sender quit / crashed / went away mid-transfer) so the UI never hangs.
UPLOAD_TIMEOUT = 20

parser = argparse.ArgumentParser()
parser.add_argument("--alias", default="pillShell Stash")
# FilesTray directory: every accepted *file* is also mirrored here so it shows
# up in the stash tray. Empty disables mirroring.
parser.add_argument("--stash-dir", default="")
args = parser.parse_args()
ALIAS = args.alias
STASH_DIR = os.path.expanduser(args.stash_dir) if args.stash_dir else ""

import hashlib

CACHE_DIR = os.path.expanduser("~/.cache/pillshell_localsend")
os.makedirs(CACHE_DIR, exist_ok=True)
CERT = os.path.join(CACHE_DIR, "cert.pem")
KEY = os.path.join(CACHE_DIR, "key.pem")

# -- identity -----------------------------------------------------------
# In LocalSend's HTTPS mode the fingerprint is the SHA-256 of the TLS
# certificate; peers (notably iOS) verify the presented cert against it,
# so it must be derived from the cert — not a random value.
if not (os.path.exists(CERT) and os.path.exists(KEY)):
    subprocess.run([
        "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
        "-keyout", KEY, "-out", CERT, "-days", "3650",
        "-subj", "/CN=pillShell Stash",
    ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

with open(CERT) as _cf:
    FINGERPRINT = hashlib.sha256(ssl.PEM_cert_to_DER_cert(_cf.read())).hexdigest()

# -- stdout/stderr helpers ----------------------------------------------
_out_lock = threading.Lock()


def emit(obj):
    with _out_lock:
        sys.stdout.write(json.dumps(obj) + "\n")
        sys.stdout.flush()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def notify(title, body, icon=None):
    try:
        cmd = ["notify-send", title, body]
        if icon:
            cmd += ["-i", icon]
        subprocess.Popen(cmd)
    except Exception:
        pass


def device_info():
    return {
        "alias": ALIAS,
        "version": "2.1",
        "deviceModel": "pillShell",
        "deviceType": "desktop",
        "fingerprint": FINGERPRINT,
        "port": PORT,
        "protocol": "https",
        "download": False,
    }


# -- session bookkeeping ------------------------------------------------
# Pending sessions wait for a QML accept/reject decision.
pending = {}        # sessionId -> {"event": Event, "decision": dict|None}
active = {}         # sessionId -> {"dir","tokens":{fid:token},"files":{fid:meta},
                    #               "done":set(),"total":int,"received":int,"lock":Lock}
_sessions_lock = threading.Lock()


def safe_name(name):
    name = os.path.basename(name or "file")
    name = name.replace("\x00", "").strip() or "file"
    # strip any sneaky separators left after basename
    return re.sub(r"[/\\]", "_", name)


def unique_path(directory, name):
    path = os.path.join(directory, name)
    if not os.path.exists(path):
        return path
    stem, ext = os.path.splitext(name)
    i = 1
    while True:
        cand = os.path.join(directory, f"{stem} ({i}){ext}")
        if not os.path.exists(cand):
            return cand
        i += 1


def is_text_message(meta):
    # A pasted/clipboard message vs a real file: LocalSend tags messages with
    # fileType "text" (desktop) or "text/plain" (mobile) AND carries the full
    # message in the `preview` field — real files never set `preview` for
    # text, so `preview` present + a text-ish type is the reliable signal.
    t = (meta.get("type") or "")
    preview = meta.get("preview")
    if t == "text":
        return True
    if t.startswith("text") and isinstance(preview, str) and preview:
        return True
    return False


# -- HTTP handler -------------------------------------------------------
class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _empty(self, code):
        self.send_response(code)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _read_body(self):
        length = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(length) if length else b""

    def _query(self):
        if "?" not in self.path:
            return {}
        out = {}
        for p in self.path.split("?", 1)[1].split("&"):
            if "=" in p:
                k, v = p.split("=", 1)
                out[k] = v
        return out

    def do_GET(self):
        if self.path.startswith("/api/localsend/v2/info"):
            self._json(200, device_info())
        else:
            self._empty(404)

    def do_POST(self):
        path = self.path.split("?", 1)[0]
        if path in ("/api/localsend/v2/info", "/api/localsend/v2/register"):
            self._read_body()
            self._json(200, device_info())
        elif path == "/api/localsend/v2/prepare-upload":
            self._prepare_upload()
        elif path == "/api/localsend/v2/upload":
            self._upload()
        elif path == "/api/localsend/v2/cancel":
            self._cancel()
        else:
            self._read_body()
            self._empty(404)

    # -- prepare-upload: emit request, block for QML decision -----------
    def _prepare_upload(self):
        try:
            body = json.loads(self._read_body().decode())
        except Exception:
            self._empty(400)
            return

        info = body.get("info", {})
        files = body.get("files", {})
        if not files:
            self._empty(204)
            return

        sid = secrets.token_hex(16)
        file_list = []
        total = 0
        for fid, meta in files.items():
            size = int(meta.get("size", 0) or 0)
            total += size
            preview = meta.get("preview")
            file_list.append({
                "id": fid,
                "name": meta.get("fileName", "file"),
                "size": size,
                "type": meta.get("fileType", ""),
                "preview": preview if isinstance(preview, str) else "",
            })

        log("prepare-upload:", [(f["name"], f["type"], bool(f["preview"]))
                                for f in file_list])

        # Pure single-message text send → expose the text so the accept card
        # can offer a "copy" affordance instead of a file row.
        text_files = [f for f in file_list if is_text_message(f)]
        is_text = len(file_list) == 1 and len(text_files) == 1
        text_body = text_files[0]["preview"] if is_text else ""

        ev = threading.Event()
        with _sessions_lock:
            pending[sid] = {"event": ev, "decision": None}

        emit({
            "event": "request",
            "sessionId": sid,
            "alias": info.get("alias", "Unknown"),
            "fingerprint": info.get("fingerprint", ""),
            "files": file_list,
            "totalSize": total,
            "isText": is_text,
            "text": text_body,
        })

        decided = ev.wait(timeout=120)
        with _sessions_lock:
            entry = pending.pop(sid, None)
        decision = entry["decision"] if entry else None

        if not decided or not decision or decision.get("action") != "accept":
            if not decided:
                emit({"event": "timeout", "sessionId": sid})
            self._empty(403)
            return

        directory = decision.get("dir") or os.path.expanduser("~/Downloads")
        os.makedirs(directory, exist_ok=True)

        tokens = {f["id"]: secrets.token_hex(16) for f in file_list}
        with _sessions_lock:
            active[sid] = {
                "dir": directory,
                "tokens": tokens,
                "files": {f["id"]: f for f in file_list},
                "done": set(),
                "total": total,
                "received": 0,
                "last_activity": time.time(),
                "lock": threading.Lock(),
            }
        self._json(200, {"sessionId": sid, "files": tokens})

    # -- upload: stream one file to disk --------------------------------
    def _upload(self):
        q = self._query()
        sid = q.get("sessionId")
        fid = q.get("fileId")
        token = q.get("token")

        with _sessions_lock:
            sess = active.get(sid)
        if not sess or sess["tokens"].get(fid) != token:
            self._read_body()  # drain
            self._empty(403)
            return

        meta = sess["files"][fid]
        dest = unique_path(sess["dir"], safe_name(meta["name"]))
        length = int(self.headers.get("Content-Length", 0))
        try:
            with open(dest, "wb") as out:
                remaining = length
                while remaining > 0:
                    chunk = self.rfile.read(min(65536, remaining))
                    if not chunk:
                        break
                    out.write(chunk)
                    remaining -= len(chunk)
                    with sess["lock"]:
                        sess["received"] += len(chunk)
                        sess["last_activity"] = time.time()
                        emit({
                            "event": "progress",
                            "sessionId": sid,
                            "received": sess["received"],
                            "total": sess["total"],
                        })
                if remaining > 0:
                    raise ConnectionError("upload truncated")
        except Exception as e:
            # Sender vanished / connection dropped mid-file: tear the session
            # down and tell QML so the panel doesn't hang on "Receiving…".
            log("upload error:", e)
            with _sessions_lock:
                still = active.pop(sid, None)
            if still is not None:
                emit({"event": "session-failed", "sessionId": sid,
                      "reason": "upload-error"})
            try:
                self._empty(500)
            except Exception:
                pass
            return

        self._empty(200)
        with sess["lock"]:
            sess["done"].add(fid)
            # A pasted/clipboard message → copy straight to the clipboard and
            # drop the temp file, while actual files are kept and mirrored into
            # the FilesTray stash dir.
            if is_text_message(meta):
                try:
                    with open(dest, "r", encoding="utf-8", errors="replace") as tf:
                        content = tf.read()
                except Exception:
                    content = ""
                if not content:
                    content = meta.get("preview") or ""
                try:
                    subprocess.run(["wl-copy"], input=content.encode(), check=False)
                except Exception:
                    pass
                try:
                    os.remove(dest)
                except Exception:
                    pass
                emit({"event": "text-received", "sessionId": sid, "text": content})
                notify("LocalSend", "Text copied to clipboard", "edit-paste")
            else:
                if STASH_DIR:
                    try:
                        os.makedirs(STASH_DIR, exist_ok=True)
                        shutil.copy2(dest, unique_path(STASH_DIR, os.path.basename(dest)))
                    except Exception as e:
                        log("stash mirror failed:", e)
                emit({"event": "file-done", "sessionId": sid,
                      "name": meta["name"], "path": dest})
                notify("LocalSend", f"Received: {meta['name']}")
            if len(sess["done"]) >= len(sess["files"]):
                emit({"event": "session-done", "sessionId": sid})
                with _sessions_lock:
                    active.pop(sid, None)

    def _cancel(self):
        q = self._query()
        self._read_body()
        sid = q.get("sessionId")
        with _sessions_lock:
            active.pop(sid, None)
            entry = pending.get(sid)
        if entry:
            entry["decision"] = {"action": "reject"}
            entry["event"].set()
        emit({"event": "cancelled", "sessionId": sid})
        self._empty(200)


# -- stdin reader: QML decisions ----------------------------------------
def stdin_loop():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except Exception:
            continue
        sid = msg.get("sessionId")
        with _sessions_lock:
            entry = pending.get(sid)
        if entry is not None:
            entry["decision"] = msg
            entry["event"].set()
    # stdin closed -> parent gone, shut down.
    os._exit(0)


# -- multicast discovery ------------------------------------------------
# Set whenever the set of local interface IPs changes (VPN up/down, network
# switch). Wakes the registration sweep so freshly-reachable peers see us
# without restarting the receive server.
_net_changed = threading.Event()


def iface_ips():
    ips = []
    try:
        out = subprocess.check_output(["ip", "-4", "-o", "addr", "show"], text=True)
        for line in out.splitlines():
            m = re.search(r"inet\s+(\d+\.\d+\.\d+\.\d+)/", line)
            if m and not m.group(1).startswith("127."):
                ips.append(m.group(1))
    except Exception:
        pass
    return ips


# Unverified TLS for outbound peer registration (LocalSend uses self-signed
# certs; peers pin by fingerprint, not CA).
_reg_ctx = ssl.create_default_context()
_reg_ctx.check_hostname = False
_reg_ctx.verify_mode = ssl.CERT_NONE


def http_register(peer, port):
    # Actively register with a peer over HTTP(S). iOS LocalSend discovers
    # peers via this registration handshake rather than multicast replies,
    # so this is what makes pillShell show up on iPhones. Try HTTPS then HTTP.
    body = json.dumps(device_info()).encode()
    for scheme, ctx in (("https", _reg_ctx), ("http", None)):
        try:
            req = urlrequest.Request(
                f"{scheme}://{peer}:{port}/api/localsend/v2/register",
                data=body, headers={"Content-Type": "application/json"},
                method="POST")
            urlrequest.urlopen(req, timeout=2, context=ctx) if ctx \
                else urlrequest.urlopen(req, timeout=2)
            return
        except Exception:
            continue


def discovery_loop():
    announce = json.dumps({**device_info(), "announce": True, "announcement": True}).encode()
    reply = json.dumps({**device_info(), "announce": False, "announcement": False}).encode()

    rx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    rx.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        rx.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    except Exception:
        pass
    rx.bind(("", PORT))
    try:
        rx.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP,
                      struct.pack("4sL", socket.inet_aton(MCAST), socket.INADDR_ANY))
    except OSError:
        pass

    # Tracks which interface IPs we've joined the multicast group on. Joining
    # is per-interface, so when a new interface appears (e.g. a VPN tun comes
    # up) we must join on it too — otherwise peers' multicast announces on that
    # network never reach us until the server restarts.
    joined = set()

    def sync_membership():
        nonlocal joined
        cur = set(iface_ips())
        for ip in cur - joined:
            try:
                rx.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP,
                              struct.pack("4s4s", socket.inet_aton(MCAST),
                                          socket.inet_aton(ip)))
            except OSError:
                pass
        for ip in joined - cur:
            try:
                rx.setsockopt(socket.IPPROTO_IP, socket.IP_DROP_MEMBERSHIP,
                              struct.pack("4s4s", socket.inet_aton(MCAST),
                                          socket.inet_aton(ip)))
            except OSError:
                pass
        changed = cur != joined
        joined = cur
        return changed

    tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    tx.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 4)

    def send(payload):
        for ip in iface_ips() or [None]:
            try:
                if ip:
                    tx.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF,
                                  socket.inet_aton(ip))
                tx.sendto(payload, (MCAST, PORT))
            except OSError:
                pass

    sync_membership()
    send(announce)
    last_announce = time.time()
    last_netcheck = time.time()
    rx.settimeout(1.0)
    while True:
        now = time.time()
        # Watch for interface changes (VPN up/down) and re-join the multicast
        # group on any new interface, then re-announce + kick the registration
        # sweep so the new network sees us immediately.
        if now - last_netcheck > 2:
            last_netcheck = now
            if sync_membership():
                send(announce)
                last_announce = now
                _net_changed.set()
        # Periodic self-announce keeps us fresh in peers' device lists.
        if now - last_announce > 5:
            send(announce)
            last_announce = now
        try:
            data, (peer, _) = rx.recvfrom(65536)
        except socket.timeout:
            continue
        except OSError:
            continue
        try:
            msg = json.loads(data.decode())
        except Exception:
            continue
        if msg.get("fingerprint") == FINGERPRINT:
            continue
        # A peer announced itself -> reply via multicast AND actively register
        # over HTTP. The multicast reply covers Android/desktop; the HTTP
        # register is what iOS needs to list us.
        if msg.get("announce") or msg.get("announcement"):
            send(reply)
            port = msg.get("port", PORT)
            threading.Thread(target=http_register, args=(peer, port),
                             daemon=True).start()


# -- watchdog: abandon stalled sessions ---------------------------------
def reaper_loop():
    while True:
        time.sleep(5)
        now = time.time()
        stale = []
        with _sessions_lock:
            for sid, sess in list(active.items()):
                if now - sess["last_activity"] > UPLOAD_TIMEOUT:
                    stale.append(sid)
                    active.pop(sid, None)
        for sid in stale:
            emit({"event": "session-failed", "sessionId": sid, "reason": "timeout"})


# -- proactive registration sweep (covers VPN / multicast-blocked peers) -
def _private_subnet_targets():
    targets, local = set(), set()
    try:
        out = subprocess.check_output(["ip", "-4", "-o", "addr", "show"], text=True)
    except Exception:
        return targets
    nets = []
    for line in out.splitlines():
        m = re.search(r"inet\s+(\d+\.\d+\.\d+\.\d+)/(\d+)", line)
        if not m:
            continue
        ip, plen = m.group(1), int(m.group(2))
        if ip.startswith("127."):
            continue
        local.add(ip)
        try:
            if not ipaddress.ip_address(ip).is_private:
                continue
        except ValueError:
            continue
        net = ipaddress.ip_network(f"{ip}/{plen}", strict=False)
        if net.num_addresses > 256:          # cap a wide VPN prefix to /24
            net = ipaddress.ip_network(f"{ip}/24", strict=False)
        nets.append(net)
    for net in nets:
        for h in net.hosts():
            targets.add(str(h))
    return targets - local


def _try_register(ip):
    # Only register with hosts that actually have the port open.
    try:
        with socket.create_connection((ip, PORT), timeout=0.4):
            pass
    except OSError:
        return
    http_register(ip, PORT)


def register_sweep_loop():
    # Periodically push our registration to every LocalSend device on the
    # subnet. iOS with a VPN often won't deliver/receive multicast, so this
    # is what keeps us discoverable there.
    time.sleep(2)
    while True:
        targets = _private_subnet_targets()
        if targets:
            with concurrent.futures.ThreadPoolExecutor(max_workers=64) as ex:
                list(ex.map(_try_register, targets))
        # Re-sweep every 30 s, but wake immediately when the network changes
        # (VPN up/down) so a peer on the freshly-added subnet sees us at once.
        _net_changed.wait(timeout=30)
        _net_changed.clear()


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def handle_error(self, request, client_address):
        # LocalSend peers routinely probe the port and drop the connection
        # (and TLS resets are normal) — don't spew tracebacks for those.
        e = sys.exc_info()[1]
        if isinstance(e, (ConnectionResetError, BrokenPipeError,
                          ConnectionAbortedError, ssl.SSLError, TimeoutError)):
            return
        super().handle_error(request, client_address)


def main():
    threading.Thread(target=stdin_loop, daemon=True).start()
    threading.Thread(target=discovery_loop, daemon=True).start()
    threading.Thread(target=reaper_loop, daemon=True).start()
    threading.Thread(target=register_sweep_loop, daemon=True).start()

    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(CERT, KEY)
    httpd = Server(("0.0.0.0", PORT), Handler)
    httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)

    emit({"event": "ready"})
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
