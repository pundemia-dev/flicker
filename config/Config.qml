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
                    topMargin: 10
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
                    startupDelayMs: 60
                })
            property var gestures: ({
                    minimalActiveZoneHeight: 42,
                    quickSettingsZoneWidth: 120,
                    quickSettingsZoneHeight: 56,
                    notificationsZoneWidth: 120,
                    notificationsZoneHeight: 56,
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
                    margin: 6
                })
            property var corners: ({
                    enabled: true,
                    rounding: 16,
                    color: "#101115"
                })
            property var effects: ({
                    disableBlur: false,
                    islandOpacity: 1.0
                })
            property var notifications: ({
                    tickerDurationMs: 3500,
                    onlyUrgentToast: true,
                    centerStripeHeight: 5,
                    centerStripeWidth: 10,
                    historyLimit: 50
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
                    transcribeCommand: ""
                })
            property var compositor: ({
                    pollMs: 1200
                })
            // Per-module island sizes (island.moduleWidth/Height = fallback).
            // "notifications" splits by payload mode: notifications:flow/center.
            property var modules: ({
                    launcher: ({ width: 560, height: 210 }),
                    quicksettings: ({ width: 560, height: 210 }),
                    dashboard: ({ width: 560, height: 210 }),
                    player: ({ width: 560, height: 210 }),
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
