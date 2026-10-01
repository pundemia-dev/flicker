pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property alias data: adapter
    property bool ready: false

    FileView {
        id: configFile
        path: `${Quickshell.shellDir}/config/config.json`
        watchChanges: true
        blockLoading: true
        onFileChanged: reload()
        onAdapterUpdated: if (root.ready) writeAdapter()
        onLoaded: root.ready = true
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound) {
                root.ready = true;
                writeAdapter();
            }
        }

        JsonAdapter {
            id: adapter
            property var island: ({
                    height: 36,
                    radius: 22,
                    maxWidth: 560,
                    moduleWidth: 560,
                    moduleHeight: 210,
                    minimalWidth: 60,
                    minimalHeight: 6,
                    minimalRadius: 4,
                    topMargin: 10,
                    haloWidth: 2,
                    haloBorder: 2
                })
            property var timings: ({
                    minimalIdleMs: 3000,
                    moduleIdleFromMinimalMs: 3000,
                    blurInMs: 110,
                    fadeInMs: 160,
                    blurOutMs: 110,
                    fadeOutMs: 160,
                    blurFadeDelayMs: 70,
                    blurKickIntervalMs: 80,
                    osdAutoCloseMs: 1300,
                    plateIconMs: 380,
                    startupDelayMs: 60,
                    startupMorphDelayMs: 100
                })
            property var gestures: ({
                    minimalActiveZoneHeight: 42,
                    quickSettingsZoneWidth: 100,
                    quickSettingsZoneHeight: 5,
                    notificationsZoneWidth: 100,
                    notificationsZoneHeight: 5,
                    clockZoneWidth: 120,
                    clockZoneHeight: 44,
                    dashboardDragThreshold: 42,
                    sideDragThreshold: 36,
                    presentationDragThreshold: 30
                })
            property var indicators: ({
                    indicatorSpacingFactor: 0.018,
                    edgePaddingFactor: 0.06,
                    musicCoverDiameter: 24,
                    micDotDiameter: 8,
                    micLabelMaxWidth: 180,
                    waveWidth: 28,
                    plateHeight: 22,
                    plateMinWidth: 46,
                    plateHPad: 20,
                    plateRadius: 11
                })
            property var arcs: ({
                    radius: 18,
                    thickness: 3,
                    margin: 6,
                    glowWidth: 12
                })
            property var corners: ({
                    enabled: true,
                    rounding: 16,
                    color: "#101115"
                })
            property var effects: ({
                    disableBlur: false,
                    disableCompositorBlur: false,
                    islandOpacity: 1.0
                })
            property var notifications: ({
                    tickerDurationMs: 3500,
                    onlyUrgentToast: true,
                    centerStripeHeight: 5,
                    centerStripeWidth: 10,
                    historyLimit: 50,
                    // Flow toast lifetime: alone vs. with more queued behind.
                    flowShowMs: 5000,
                    flowShowQueuedMs: 3000,
                    // Collapse-to-bar pause between queued flow cards.
                    flowSwapGapMs: 300,
                    // Notification card: left avatar/icon diameter; the app-icon
                    // badge overlapping the avatar's bottom-right rim.
                    avatarSize: 56,
                    badgeSize: 16
                })
            property var battery: ({
                    warnPercent: 50,
                    lowPercent: 20
                })
            property var audio: ({
                    maxVolume: 1.5,
                    volumeStep: 0.05,
                    // Capture streams to hide from the mic indicator:
                    // case-insensitive substrings matched against
                    // application.name, process binary, description and node
                    // name (e.g. DSP infrastructure nodes). Empty = show all.
                    micExclude: []
                })
            property var brightness: ({
                    step: 0.1
                })
            property var network: ({
                    pollMs: 4000,
                    hotspotName: "Hotspot"
                })
            property var recorder: ({
                    outputFile: "/tmp/pillShell-recording.mp4",
                    pidFile: "/tmp/pillShell-rec.pid"
                })
            property var dictation: ({
                    captureFile: "/tmp/pillShell-dictation.wav",
                    transcribeCommand: "",
                    // STT language: "auto" lets the engine detect ru/en on the
                    // fly; "ru"/"en" pins it (faster + more accurate).
                    language: "auto",
                    // Pacing hint for the test stub backend (DICT_CHUNK_MS).
                    // The realtime backend reads the mic in small fixed
                    // frames and the model's own chunking lives server-side
                    // (`nemo-speech serve`), so this changes no ASR latency.
                    chunkMs: 800,
                    // Streaming backend: "" = legacy batch (pw-record +
                    // transcribeCommand), "stub" = built-in test emitter,
                    // otherwise a shell command printing JSONL partial/final
                    // lines (see scripts/dictation/stream-nemotron.sh).
                    streamCommand: "stub",
                    // Text->text segment finalizer (receives segment as $1,
                    // lang as $2, stdout = improved text). "" = skip.
                    finalizerCommand: "",
                    // Gemma 4 E2B Refine over llama-server (OpenAI-compatible).
                    refineEnabled: false,
                    refineUrl: "http://127.0.0.1:8080/v1/chat/completions",
                    refineModel: "gemma-4-E2B-it-Q4_K_M",
                    refinePrompt: "Ты — движок чистки диктовки, а не чат-бот. Выведи ТОЛЬКО очищенный текст.",
                    refineTimeoutS: 15,
                    // Typing is wtype-only (no clipboard path by decision).
                    // typeEnabled false = headless/dry-run (no typing).
                    typeEnabled: true,
                    typeDelayMs: 0,
                    // Follow the compositor keyboard layout: the session
                    // language comes from services/KeyboardLayout (mapped
                    // through layout2lang) instead of `language` below.
                    // Unmapped/unknown layouts fall back to `language`.
                    followLayout: true,
                    // Layout-switch mode: "restart" (stop with flush, start
                    // a new session in the new language — fast, but a
                    // mid-utterance switch splits the phrase). "dual"
                    // (hot ru+en sessions, zero-latency routing) is PLANNED,
                    // not implemented — anything but "restart" warns and
                    // behaves as "restart".
                    switchMode: "restart",
                    // XKB layout → ASR language. Keyed by short code ("us")
                    // or full name ("English (US)"); extend for your setup.
                    layout2lang: ({
                        us: "en",
                        ru: "ru",
                        "English (US)": "en",
                        "Russian": "ru"
                    }),
                    // Stop watchdog: a backend deaf to SIGINT is SIGKILLed
                    // after this. Budget: terminate+drain+commit+~2.5s
                    // trailing decode + margin. A watchdog kill during a
                    // graceful stop finishes off the tailed file, not _fail.
                    stopTimeoutMs: 7000,
                    logFile: "/tmp/pillShell-dictation.jsonl",
                    // Hallucination drop-list: keep SHORT and engine-
                    // specific. Whole-match only, but a real utterance
                    // equal to a list entry is still dropped silently —
                    // Nemotron (unlike Whisper) is not known to emit such
                    // phrases, so the default stays empty.
                    hallucinations: []
                })
            property var compositor: ({
                    pollMs: 1200
                })
            property var dashboard: ({
                    // "" = auto by IP, "City" name, or "lat,lon".
                    weatherLocation: "",
                    useFahrenheit: false,
                    sysPollMs: 2000,
                    weatherPollMs: 1800000,
                    updatesPollMs: 900000,
                    cardRadius: 13,
                    spacing: 8,
                    margins: 9,
                    cardPadding: 10,
                    // Grid-first layout: unit side (px) + column count. Row
                    // count emerges from card spans. Island size must match:
                    // W/H = 2*margins + 5*unit + 4*spacing (modules.dashboard).
                    unit: 80,
                    cols: 6,
                    titleSize: 13,
                    dotSize: 8,
                    valueSize: 24,
                    bigValueSize: 32,
                    headerTimeSize: 44,
                    headerDateSize: 15,
                    iconSize: 24
                })
            // Per-module island sizes (island.moduleWidth/Height = fallback).
            // "notifications" splits by payload mode: notifications:flow/center.
            property var modules: ({
                    launcher: ({ width: 560, height: 210 }),
                    quicksettings: ({ width: 560, height: 210 }),
                    dashboard: ({ width: 538, height: 450 }),
                    player: ({ width: 448, height: 230 }),
                    notifications: ({ width: 520, height: 180 }),
                    "notifications:flow": ({ width: 520, height: 150 }),
                    "notifications:center": ({ width: 560, height: 210 }),
                    osd: ({ width: 400, height: 72 }),
                    capture: ({ width: 520, height: 112 }),
                    dictation: ({ width: 480, height: 132 }),
                    localsend: ({ width: 440, height: 120 }),
                    "recording-actions": ({ width: 360, height: 84 }),
                    "hotspot-actions": ({ width: 360, height: 84 })
                })
            property var capture: ({
                    screenshotFile: "/tmp/pillShell-shot.png",
                    aiFile: "/tmp/pillShell-ai.png"
                })
        }
    }
}
