#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
#
# Send one or more files to a LocalSend device in a single session.
# Usage: localsend_send.py <target-ip> <file> [<file> ...]

import sys, os, json, ssl, hashlib, subprocess, mimetypes
from urllib import request

PORT = 53317


def notify(body, icon="emblem-ok-symbolic"):
    try:
        subprocess.Popen(["notify-send", "LocalSend", body, "-i", icon])
    except Exception:
        pass


def die(msg):
    notify(msg, "dialog-error")
    sys.exit(1)


if len(sys.argv) < 3:
    die("Usage: localsend_send.py <target-ip> <file...>")

TARGET = sys.argv[1]
ARG_FILES = sys.argv[2:]

if not TARGET:
    die("No target device specified")

# Build per-file metadata + the prepare-upload payload. Each file gets a
# stable id so we can match the upload token the receiver hands back.
entries = {}        # file_id -> {"path","name","type"}
files_payload = {}  # file_id -> LocalSend file descriptor
for path in ARG_FILES:
    if not path or not os.path.isfile(path):
        continue
    name = os.path.basename(path)
    size = os.path.getsize(path)
    try:
        ftype = subprocess.check_output(
            ["file", "-b", "--mime-type", path], text=True).strip()
    except Exception:
        ftype = mimetypes.guess_type(path)[0] or "application/octet-stream"
    fid = "ps_" + hashlib.md5(os.urandom(16)).hexdigest()[:8]
    entries[fid] = {"path": path, "name": name, "type": ftype}
    files_payload[fid] = {
        "id": fid,
        "fileName": name,
        "size": size,
        "fileType": ftype,
        "sha256": None,
        "preview": None,
        "metadata": None,
    }

if not files_payload:
    die("No files found")

# Identity fingerprint = SHA-256 of our TLS cert (shared with the receive
# server in ~/.cache/pillshell_localsend). Generated on demand if absent so
# sending works even when the receive server has never run.
CACHE_DIR = os.path.expanduser("~/.cache/pillshell_localsend")
CERT = os.path.join(CACHE_DIR, "cert.pem")
KEY = os.path.join(CACHE_DIR, "key.pem")
if not (os.path.exists(CERT) and os.path.exists(KEY)):
    os.makedirs(CACHE_DIR, exist_ok=True)
    subprocess.run([
        "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
        "-keyout", KEY, "-out", CERT, "-days", "3650", "-subj", "/CN=pillShell Stash",
    ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
with open(CERT) as _cf:
    FINGERPRINT = hashlib.sha256(ssl.PEM_cert_to_DER_cert(_cf.read())).hexdigest()

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE


def post(path, data, headers, timeout):
    req = request.Request(f"https://{TARGET}:{PORT}{path}", data=data,
                          headers=headers, method="POST")
    return request.urlopen(req, timeout=timeout, context=ctx)


body = json.dumps({
    "info": {
        "alias": "pillShell Stash",
        "version": "2.1",
        "deviceModel": "pillShell",
        "deviceType": "desktop",
        "fingerprint": FINGERPRINT,
        "port": PORT,
        "protocol": "https",
        "download": False,
    },
    "files": files_payload,
}).encode()

try:
    resp = post("/api/localsend/v2/prepare-upload", body,
                {"Content-Type": "application/json"}, 30)
    prep = json.loads(resp.read().decode())
except Exception:
    die("Rejected or timed out")

SESSION = prep.get("sessionId", "")
TOKENS = prep.get("files", {})  # file_id -> token (only accepted files)
if not SESSION or not TOKENS:
    die("Rejected or timed out")

sent = 0
last_name = ""
for fid, meta in entries.items():
    token = TOKENS.get(fid)
    if not token:
        continue
    try:
        with open(meta["path"], "rb") as f:
            post(f"/api/localsend/v2/upload?sessionId={SESSION}&fileId={fid}&token={token}",
                 f.read(), {"Content-Type": meta["type"]}, 120)
        sent += 1
        last_name = meta["name"]
    except Exception:
        pass

if sent == 0:
    die("Upload failed")
notify(f"Sent {sent} files" if sent > 1 else f"Sent: {last_name}")
