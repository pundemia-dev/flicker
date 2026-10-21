import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// KeyboardLayout: tracks the compositor's active keyboard layout and maps it
// to an ASR language via Config dictation.layout2lang (keyed by short code
// like "us" or by full XKB name like "English (US)" — XKB names vary, so the
// table is user config, never hardcoded).
//
// drift: one-shot `driftwm msg --json state` for the initial value, then a
// long-lived `driftwm msg subscribe --json` tail (snapshots carry
// layout/layout_short; window traffic is parsed but ignored). Snapshots only
// go out after a rendered frame — poll() re-reads `state` (the lock does it
// after non-text keys).
// niri: long-lived `niri msg --json event-stream`; the stream replays
// KeyboardLayoutsChanged on connect, then KeyboardLayoutSwitched per tap.
// hyprland: one-shot `hyprctl -j devices` (main keyboard's active_keymap),
// then `activelayout>>KEYBOARD,LAYOUT` lines on the event socket
// (.socket2.sock); virtual keyboards (wtype/dictation typer) are ignored.
// Anything else is untracked: lang stays "" and dictation
// falls back to its configured language.
Item {
    id: root

    property string layout: ""
    property string code: ""
    property string lang: ""

    signal switched(string lang, string layout)

    readonly property string _backend: {
        const niriSocket = Quickshell.env("NIRI_SOCKET") ?? "";
        if (niriSocket.length > 0)
            return "niri";
        const desktop = (Quickshell.env("XDG_CURRENT_DESKTOP") ?? "").toLowerCase();
        if (desktop.indexOf("drift") !== -1)
            return "drift";
        if ((Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? "").length > 0)
            return "hyprland";
        return "";
    }

    property var _niriNames: []
    property int _niriIdx: -1

    function _mapLang(code: string, layout: string): string {
        const t = Config.data.dictation.layout2lang ?? ({});
        const c = t[code] ?? "";
        if ((c ?? "").length > 0)
            return c;
        const n = t[layout] ?? "";
        return n ?? "";
    }

    function _set(layout: string, code: string): void {
        const l = layout ?? "";
        const c = code ?? "";
        if (l === root.layout && c === root.code)
            return;
        root.layout = l;
        root.code = c;
        const mapped = root._mapLang(c, l);
        if (mapped.length === 0) {
            if (l.length > 0 || c.length > 0)
                console.warn("[KeyboardLayout] no lang mapping for", JSON.stringify({ layout: l, code: c }));
            return;
        }
        if (mapped !== root.lang) {
            root.lang = mapped;
            root.switched(mapped, l);
        }
    }

    function _applyNiri(): void {
        const names = root._niriNames;
        const i = root._niriIdx;
        if (i >= 0 && i < names.length)
            root._set(names[i] ?? "", "");
    }

    function _startWatcher(): void {
        if (root._backend === "drift") {
            if (!driftSub.running) {
                driftSub.command = ["driftwm", "msg", "subscribe", "--json"];
                driftSub.running = true;
            }
        } else if (root._backend === "hyprland") {
            hyprEvents.connected = true;
        } else if (root._backend === "niri") {
            if (!niriSub.running) {
                niriSub.command = ["niri", "msg", "--json", "event-stream"];
                niriSub.running = true;
            }
        }
    }

    // Ask again now (drift only; niri pushes every switch). driftwm sends its
    // subscribe snapshots only after a RENDERED frame, so a layout switch on
    // a static screen (the lock) stays unreported until something redraws.
    function poll(): void {
        if (root._backend === "drift" && !driftInit.running)
            driftInit.running = true;
    }

    Component.onCompleted: {
        if (root._backend === "drift") {
            driftInit.command = ["driftwm", "msg", "--json", "state"];
            driftInit.running = true;
            root._startWatcher();
        } else if (root._backend === "hyprland") {
            hyprInit.running = true;
            root._startWatcher();
        } else if (root._backend === "niri") {
            root._startWatcher();
        }
    }

    Process {
        id: hyprInit
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const kbs = JSON.parse(text ?? "")?.keyboards ?? [];
                    const kb = kbs.find(k => k.main) ?? kbs.find(k => (k.name ?? "").indexOf("virtual") === -1) ?? null;
                    if (kb)
                        root._set(kb.active_keymap ?? "", "");
                } catch (e) {
                    console.warn("[KeyboardLayout] hyprland devices parse:", e);
                }
            }
        }
    }

    Socket {
        id: hyprEvents
        path: {
            const sig = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? "";
            return sig.length > 0 ? `${Quickshell.env("XDG_RUNTIME_DIR") ?? ""}/hypr/${sig}/.socket2.sock` : "";
        }
        parser: SplitParser {
            onRead: line => {
                const l = line ?? "";
                if (!l.startsWith("activelayout>>"))
                    return;
                const body = l.slice("activelayout>>".length);
                const comma = body.indexOf(",");
                if (comma < 0 || body.slice(0, comma).indexOf("virtual") !== -1)
                    return;
                root._set(body.slice(comma + 1), "");
            }
        }
        onConnectedChanged: {
            if (!connected && root._backend === "hyprland") {
                console.warn("[KeyboardLayout] hyprland event socket closed — retrying");
                retryTimer.restart();
            }
        }
    }

    Process {
        id: driftInit
        stdout: StdioCollector {
            onStreamFinished: {
                if (root._backend !== "drift")
                    return;
                try {
                    const st = JSON.parse(text ?? "")?.Ok?.State;
                    if (st)
                        root._set(st.layout ?? "", st.layout_short ?? "");
                } catch (e) {
                    console.warn("[KeyboardLayout] drift state parse:", e);
                }
            }
        }
    }

    Process {
        id: driftSub
        stdout: SplitParser {
            onRead: line => {
                if (root._backend !== "drift")
                    return;
                let st = null;
                try {
                    st = JSON.parse(line ?? "")?.State;
                } catch (e) {
                    return;
                }
                if (st)
                    root._set(st.layout ?? "", st.layout_short ?? "");
            }
        }
        onExited: code => {
            if (root._backend !== "drift")
                return;
            console.warn("[KeyboardLayout] drift subscribe exited", code, "— retrying");
            retryTimer.restart();
        }
    }

    Process {
        id: niriSub
        stdout: SplitParser {
            onRead: line => {
                if (root._backend !== "niri")
                    return;
                let ev = null;
                try {
                    ev = JSON.parse(line ?? "");
                } catch (e) {
                    return;
                }
                if (!ev)
                    return;
                if (ev.KeyboardLayoutsChanged) {
                    const kb = ev.KeyboardLayoutsChanged.keyboard_layouts;
                    root._niriNames = kb?.names ?? [];
                    root._niriIdx = kb?.current_idx ?? 0;
                    root._applyNiri();
                } else if (ev.KeyboardLayoutSwitched) {
                    root._niriIdx = ev.KeyboardLayoutSwitched.idx ?? 0;
                    root._applyNiri();
                }
            }
        }
        onExited: code => {
            if (root._backend !== "niri")
                return;
            console.warn("[KeyboardLayout] niri event-stream exited", code, "— retrying");
            retryTimer.restart();
        }
    }

    Timer {
        id: retryTimer
        interval: 5000
        onTriggered: root._startWatcher()
    }
}
