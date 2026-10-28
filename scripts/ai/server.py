#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "httpx",
#     "g4f>=7.7.1",
#     "curl-cffi>=0.15.0",
# ]
# ///
"""
Flicker AI backend (port of pShell scripts/ai_server.py; services/Ai.qml
starts it on the first request). Listens on a Unix socket, streams responses
as newline-delimited JSON:
  {"type":"delta",  "text":"…"}
  {"type":"done",   "inputTokens":N, "outputTokens":M}
  {"type":"error",  "message":"…"}
  {"type":"models", "models":[…]}     (for discovery actions)

Who may talk to it (any process of the same user can reach a 0600 socket,
and could read a token from /proc/<pid>/environ):
  1. The kernel-reported peer (SO_PEERCRED) must be THE quickshell process
     that started this server (the first quickshell among our ancestors,
     by /proc/<pid>/exe) and our uid. Unforgeable from user space: services/
     Ai.qml connects itself (Quickshell.Io Socket), no helper process.
  2. Every request carries the session token — generated HERE (secrets),
     handed to quickshell on our stdout pipe only (never argv / environ),
     compared in constant time.
Everything else is dropped without an answer (one stderr line). The socket
lives in a private 0700 directory, bound under umask 077 (no window where
it is reachable before a chmod).
"""
import asyncio, hmac, json, os, secrets, signal, socket, struct, sys
from pathlib import Path

# IPv4 only: IPv6 is broken on some networks and a connect would stall on
# it first (scripts/lyrics/fetch.py does the same). Covers httpx/aiohttp;
# curl-cffi resolves on its own (libcurl falls back by itself).
_orig_getaddrinfo = socket.getaddrinfo


def _v4_getaddrinfo(host, port, family=0, *args, **kwargs):
    if family in (0, socket.AF_INET6):
        family = socket.AF_INET
    return _orig_getaddrinfo(host, port, family, *args, **kwargs)


socket.getaddrinfo = _v4_getaddrinfo

import httpx

SESSION_TOKEN = secrets.token_urlsafe(32)
SOCKET_PATH   = os.environ.get("QS_AI_SOCKET", "")
MAX_REQUEST   = 4 * 1024 * 1024

# ── Provider helpers ─────────────────────────────────────────────────────────

async def stream_openai(endpoint: str, api_key: str, payload: dict):
    headers = {"Content-Type": "application/json",
               "Authorization": f"Bearer {api_key}"}
    payload = {**payload, "stream": True}
    async with httpx.AsyncClient(timeout=120.0) as client:
        async with client.stream("POST", endpoint, headers=headers, json=payload) as r:
            if r.status_code != 200:
                body = await r.aread()
                yield {"type": "error", "message": f"HTTP {r.status_code}: {body.decode()[:300]}"}
                return
            in_think = False
            in_tokens = out_tokens = -1
            async for line in r.aiter_lines():
                if not line.startswith("data: "):
                    continue
                data = line[6:].strip()
                if data == "[DONE]":
                    break
                try:
                    obj = json.loads(data)
                    if "error" in obj:
                        yield {"type": "error", "message": obj["error"].get("message", str(obj["error"]))}
                        return
                    delta = obj.get("choices", [{}])[0].get("delta", {})
                    reasoning = delta.get("reasoning") or delta.get("reasoning_content") or ""
                    text      = delta.get("content") or ""
                    if reasoning:
                        if not in_think:
                            in_think = True
                            yield {"type": "delta", "text": "\n\n<think>\n\n"}
                        yield {"type": "delta", "text": reasoning}
                    if text:
                        if in_think:
                            in_think = False
                            yield {"type": "delta", "text": "\n\n</think>\n\n"}
                        yield {"type": "delta", "text": text}
                    if obj.get("usage"):
                        u = obj["usage"]
                        in_tokens  = u.get("prompt_tokens", -1)
                        out_tokens = u.get("completion_tokens", -1)
                except Exception:
                    pass
            # Most providers never send `usage` in the stream — always emit
            # `done` so the client isn't left waiting for a terminator.
            yield {"type": "done", "inputTokens": in_tokens, "outputTokens": out_tokens}


async def stream_anthropic(api_key: str, payload: dict):
    messages = payload.get("messages", [])
    system   = next((m["content"] for m in messages if m["role"] == "system"), None)
    body = {
        "model":      payload["model"],
        "max_tokens": payload.get("maxTokens", 8192),
        "messages":   [m for m in messages if m["role"] != "system"],
        "stream":     True,
    }
    if system:
        body["system"] = system
    headers = {"x-api-key": api_key, "anthropic-version": "2023-06-01",
                "content-type": "application/json"}
    async with httpx.AsyncClient(timeout=120.0) as client:
        async with client.stream("POST", "https://api.anthropic.com/v1/messages",
                                  headers=headers, json=body) as r:
            if r.status_code != 200:
                b = await r.aread()
                yield {"type": "error", "message": f"HTTP {r.status_code}: {b.decode()[:300]}"}
                return
            in_tokens = out_tokens = -1
            async for line in r.aiter_lines():
                if not line.startswith("data: "):
                    continue
                try:
                    obj = json.loads(line[6:])
                    t = obj.get("type", "")
                    if t == "content_block_delta":
                        text = obj.get("delta", {}).get("text", "")
                        if text:
                            yield {"type": "delta", "text": text}
                    elif t == "message_start":
                        u = obj.get("message", {}).get("usage", {})
                        in_tokens = u.get("input_tokens", -1)
                    elif t == "message_delta":
                        u = obj.get("usage", {})
                        out_tokens = u.get("output_tokens", -1)
                    elif t == "message_stop":
                        break
                except Exception:
                    pass
    yield {"type": "done", "inputTokens": in_tokens, "outputTokens": out_tokens}


async def stream_g4f(model_name: str, messages: list):
    # Uses the modern client API: the legacy g4f.ChatCompletion path is broken
    # in g4f 7.x ("'str' object has no attribute 'working'").
    # Only keyless providers that do NOT drive a browser: g4f's default
    # RetryProvider includes nodriver ones (OpenaiChat & co.) that launch a
    # real Chrome window on the desktop to grab cookies (seen with gpt-4).
    try:
        from g4f.client import AsyncClient
        from g4f.providers.retry_provider import IterListProvider
        free = _g4f_free_map()      # imports the providers first
        _g4f_no_browser()
        provs = [p for p in free.get(model_name, []) if not _g4f_uses_browser(p)]
        if not provs:
            yield {"type": "error",
                   "message": f"g4f: no keyless provider without a browser for {model_name}"}
            return
        client = AsyncClient(provider=IterListProvider(provs, shuffle=False))
        # With stream=True this returns an async generator (not awaitable).
        response = client.chat.completions.create(
            messages=messages,
            model=model_name,
            stream=True,
        )
        async for chunk in response:
            try:
                delta = chunk.choices[0].delta.content
            except (AttributeError, IndexError):
                delta = None
            if delta:
                yield {"type": "delta", "text": delta}
        yield {"type": "done", "inputTokens": -1, "outputTokens": -1}
    except Exception as e:
        yield {"type": "error", "message": str(e)}


# Names through which g4f providers reach a real browser (zendriver /
# Chrome DevTools). `use_nodriver` is NOT reliable: ChatGPT (CDPSession)
# reports False and still opened a Chrome window.
_BROWSER_NAMES = ("get_nodriver", "get_nodriver_session", "get_args_from_nodriver",
                  "CDPSession", "nodriver", "zendriver")


def _g4f_uses_browser(cls) -> bool:
    if getattr(cls, "use_nodriver", False):
        return True
    for klass in getattr(cls, "__mro__", (cls,)):
        mod = sys.modules.get(getattr(klass, "__module__", ""))
        if mod is not None and any(n in vars(mod) for n in _BROWSER_NAMES):
            return True
    return False


def _g4f_no_browser():
    """Belt and braces: every browser entry point of g4f raises instead."""
    def refuse(*_a, **_k):
        raise RuntimeError("browser providers are disabled in Flicker")

    for mod in list(sys.modules.values()):
        name = getattr(mod, "__name__", "") or ""
        if not name.startswith("g4f"):
            continue
        for n in ("get_nodriver", "get_nodriver_session", "get_args_from_nodriver"):
            if hasattr(mod, n):
                try:
                    setattr(mod, n, refuse)
                except Exception:
                    pass


async def get_ollama_models() -> list[str]:
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            r = await client.get("http://localhost:11434/api/tags")
            if r.status_code == 200:
                return [m["name"] for m in r.json().get("models", [])]
    except Exception:
        pass
    return []


def _g4f_free_map() -> dict[str, list]:
    """model name -> keyless candidate provider classes (text models only).

    ModelUtils.convert is keyed by the REAL model names g4f accepts
    (e.g. "o4-mini-high"); dir(g4f.models) would give the python attribute
    names ("o4_mini_high"), which g4f rejects. Model.best_provider.providers
    holds provider NAMES (strings) in g4f 7.x — resolve them through the
    provider map to read the class attributes (working / needs_auth).
    """
    import g4f.models as gm
    import g4f.Provider as gp
    from g4f.models import ModelUtils

    mapping = getattr(gp, "__map__", None) or gp.ProviderUtils.convert

    # Text chat only — image/audio/video models can't be rendered here.
    non_text = tuple(t for t in (
        getattr(gm, "ImageModel", None),
        getattr(gm, "AudioModel", None),
        getattr(gm, "VideoModel", None),
    ) if t is not None)

    out: dict[str, list] = {}
    for name, model in ModelUtils.convert.items():
        if non_text and isinstance(model, non_text):
            continue
        bp = model.best_provider
        if bp is None:
            continue
        provs = getattr(bp, "providers", None) or [bp]
        keyless = []
        for p in provs:
            if isinstance(p, str):
                p = mapping.get(p)
            if p is not None and getattr(p, "working", False) \
                    and not getattr(p, "needs_auth", False):
                keyless.append(p)
        if keyless:
            out[name] = keyless
    return out


def get_g4f_models() -> list[str]:
    """Fast attribute-based list (optimistic; some providers lie)."""
    try:
        names = sorted(_g4f_free_map().keys())
        if names:
            return names
    except Exception:
        pass
    return ["gpt-4", "gpt-4o-mini", "gemini-pro", "llama-3-70b"]


# Providers verified alive this session ({name: bool}); probed once.
_g4f_alive: dict[str, bool] | None = None

PROBE_TIMEOUT = 20.0


async def _probe_provider(cls) -> bool:
    """One tiny real request through a single provider. The class attributes
    (needs_auth etc.) are unreliable — e.g. HuggingFace claims keyless but
    raises MissingAuthError at call time — so only a live answer counts."""
    try:
        from g4f.client import AsyncClient
        model = getattr(cls, "default_model", "") \
            or (getattr(cls, "models", None) or [""])[0]
        client = AsyncClient(provider=cls)
        response = client.chat.completions.create(
            messages=[{"role": "user", "content": "Hi"}],
            model=model,
            stream=True,
        )

        async def read_first():
            async for chunk in response:
                try:
                    if chunk.choices[0].delta.content:
                        return True
                except (AttributeError, IndexError):
                    pass
            return False

        return bool(await asyncio.wait_for(read_first(), timeout=PROBE_TIMEOUT))
    except Exception:
        return False


async def get_g4f_models_live() -> list[str]:
    """Models with at least one provider that actually answered a probe.

    Providers driving a browser are NOT probed and NOT offered — a probe (or
    a chat) pops a Chrome window on the user's desktop (_g4f_uses_browser).
    Results are cached per server run.
    """
    global _g4f_alive
    try:
        free_map = _g4f_free_map()

        classes = {}
        for provs in free_map.values():
            for p in provs:
                classes[p.__name__] = p

        if _g4f_alive is None:
            probed: dict[str, bool] = {}
            names, tasks = [], []
            for name, cls in classes.items():
                if _g4f_uses_browser(cls):
                    probed[name] = False  # would open a browser window
                    continue
                names.append(name)
                tasks.append(_probe_provider(cls))
            results = await asyncio.gather(*tasks, return_exceptions=True)
            for name, res in zip(names, results):
                probed[name] = res is True
            _g4f_alive = probed

        alive = _g4f_alive
        return sorted(n for n, provs in free_map.items()
                      if any(alive.get(p.__name__, False) for p in provs))
    except Exception:
        return []


# ── Request dispatcher ────────────────────────────────────────────────────────

async def dispatch(request: dict):
    action = request.get("action", "chat")

    if action == "models_ollama":
        models = await get_ollama_models()
        yield {"type": "models", "models": models}
        yield {"type": "done"}
        return

    if action == "models_g4f":
        # Two-stage: the fast attribute-based list immediately, then the
        # probe-verified list once live checks finish (the client applies
        # every `models` line it receives, so the picker just refines).
        yield {"type": "models", "models": get_g4f_models()}
        live = await get_g4f_models_live()
        if live:
            yield {"type": "models", "models": live}
        yield {"type": "done"}
        return

    fmt      = request.get("format", "openai")
    model    = request.get("model", "")
    messages = request.get("messages", [])
    api_key  = request.get("apiKey", "")
    endpoint = request.get("endpoint", "")

    if fmt == "anthropic":
        gen = stream_anthropic(api_key, {
            "model": model, "messages": messages,
            "maxTokens": request.get("maxTokens", 8192),
        })
    elif fmt == "g4f":
        gen = stream_g4f(model, messages)
    else:
        payload = {
            "model":       model,
            "messages":    messages,
            "temperature": request.get("temperature", 0.7),
        }
        if request.get("maxTokens"):
            payload["max_tokens"] = request["maxTokens"]
        gen = stream_openai(endpoint, api_key, payload)

    async for chunk in gen:
        yield chunk


# ── Socket server ─────────────────────────────────────────────────────────────

def _ppid(pid: int) -> int:
    with open(f"/proc/{pid}/stat") as f:
        # comm may contain spaces / parens: ppid is the 2nd field after ")".
        return int(f.read().rsplit(")", 1)[1].split()[1])


def _exe(pid: int) -> str:
    try:
        return os.readlink(f"/proc/{pid}/exe")
    except OSError:
        return ""


def find_shell_pid() -> int:
    """The quickshell process that (via uv) started us, 0 = none."""
    pid = os.getppid()
    while pid > 1:
        if os.path.basename(_exe(pid)).startswith("quickshell"):
            return pid
        pid = _ppid(pid)
    return 0


SHELL_PID = 0
SHELL_EXE = ""


def peer_allowed(writer: asyncio.StreamWriter) -> bool:
    sock = writer.get_extra_info("socket")
    if sock is None:
        return False
    pid, uid, _gid = struct.unpack("3i", sock.getsockopt(
        socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i")))
    ok = uid == os.getuid() and pid == SHELL_PID and _exe(pid) == SHELL_EXE
    if not ok:
        print(f"refused connection from pid {pid} uid {uid} ({_exe(pid) or '?'})",
              file=sys.stderr, flush=True)
    return ok


async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    try:
        if not peer_allowed(writer):
            return
        raw = await reader.readline()
        if not raw:
            return
        request = json.loads(raw.decode("utf-8"))

        token = request.pop("token", "")
        if not isinstance(token, str) or not hmac.compare_digest(token.encode(), SESSION_TOKEN.encode()):
            print("refused request: bad token", file=sys.stderr, flush=True)
            return

        async for chunk in dispatch(request):
            writer.write(json.dumps(chunk).encode() + b"\n")
            await writer.drain()

    except Exception as e:
        try:
            writer.write(json.dumps({"type": "error", "message": str(e)}).encode() + b"\n")
            await writer.drain()
        except Exception:
            pass
    finally:
        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass


async def watch_parent():
    """Exit when quickshell is gone (a restart would leave an orphan, and its
    pid could be reused by an unrelated process)."""
    parent = os.getppid()
    while True:
        await asyncio.sleep(2)
        if os.getppid() != parent or _exe(SHELL_PID) != SHELL_EXE:
            os._exit(0)


def private_dir(path: Path) -> None:
    """A 0700 directory we own (refuse a symlink / someone else's)."""
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    st = os.lstat(path)
    import stat as st_mod
    if not st_mod.S_ISDIR(st.st_mode) or st.st_uid != os.getuid():
        raise SystemExit(f"unsafe socket directory: {path}")
    os.chmod(path, 0o700)


def sweep_stale_sockets():
    """Remove leftover sockets of dead servers (a hard-killed server — e.g.
    on quickshell reload — never reaches its unlink)."""
    for p in Path(SOCKET_PATH).parent.glob("flicker-ai-*.sock"):
        if str(p) == SOCKET_PATH:
            continue
        try:
            c = socket.socket(socket.AF_UNIX)
            c.settimeout(0.2)
            c.connect(str(p))
            c.close()          # alive — leave it
        except OSError:
            try:
                p.unlink()
            except OSError:
                pass


async def main():
    global SHELL_PID, SHELL_EXE
    if not SOCKET_PATH:
        print("Error: QS_AI_SOCKET not set", file=sys.stderr, flush=True)
        sys.exit(1)
    SHELL_PID = find_shell_pid()
    SHELL_EXE = _exe(SHELL_PID)
    if not SHELL_PID:
        print("Error: not started by quickshell — refusing to serve", file=sys.stderr, flush=True)
        sys.exit(1)

    sock = Path(SOCKET_PATH)
    private_dir(sock.parent)
    if sock.exists() or sock.is_symlink():
        sock.unlink()
    sweep_stale_sockets()

    os.umask(0o077)
    server = await asyncio.start_unix_server(handle_client, path=SOCKET_PATH, limit=MAX_REQUEST)
    os.chmod(SOCKET_PATH, 0o600)

    # The token goes to quickshell over our stdout pipe, nowhere else.
    print(f"ready:{json.dumps({'socket': SOCKET_PATH, 'token': SESSION_TOKEN})}", flush=True)

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, server.close)

    asyncio.ensure_future(watch_parent())

    try:
        async with server:
            await server.serve_forever()
    except asyncio.CancelledError:
        pass
    finally:
        if sock.exists():
            sock.unlink()


asyncio.run(main())
