import QtQuick
import Quickshell
import "../config"

// Sources of status indicators (services/Statuses): each Feed posts its
// status while `on` and drops it after. A feed with an `event` also
// announces the start as an event tagged `status: key` (the ring then sits
// inline at the island's right end until the event hides and the drop
// splits off). Transcription and Shazam post their own events (they
// already carry live texts) — see services/Transcribe.qml / Shazam.qml.
Scope {
    id: root
    required property var statuses
    required property var events
    required property var countdown
    required property var transcribe
    required property var shazam
    required property var recorder
    required property var localSend
    required property var semantic

    readonly property var cfg: Config.data.status

    // A process must run `delay` ms before it is announced (status + start
    // event): a flicker of `on` (the wallpaper index wakes, finds nothing to
    // do, reports done at once) spread the island for a split second.
    component Feed: QtObject {
        id: feed
        required property var hub
        required property var bus
        required property string key
        property bool on: false
        property int delay: Config.data.status.announceDelayMs ?? 1000
        // Status fields (priority / color / progress / open).
        property var entry: ({})
        // Start event (null = none): { glyph?, icon?, color?, text }.
        property var event: null
        property bool posted: false
        property Timer wait: Timer {
            interval: Math.max(1, feed.delay)
            onTriggered: feed.sync()
        }
        onOnChanged: {
            if (feed.on && feed.delay > 0 && !feed.posted)
                feed.wait.restart();
            else
                feed.sync();
        }
        Component.onCompleted: if (feed.on) feed.wait.restart()
        function sync(): void {
            feed.wait.stop();
            feed.posted = feed.on;
            if (feed.on) {
                feed.hub.post(Object.assign({ key: feed.key }, feed.entry));
                if (feed.event)
                    feed.bus.post(Object.assign({ key: "status:" + feed.key, status: feed.key }, feed.event));
            } else {
                feed.hub.cancel(feed.key);
                if (feed.event)
                    feed.bus.cancel("status:" + feed.key);
            }
        }
    }

    property Feed timer: Feed {
        hub: root.statuses
        bus: root.events
        key: "timer"
        delay: 0
        on: (root.cfg.timer ?? true) && (root.countdown?.active ?? false)
        entry: ({
                priority: 100,
                color: () => root.countdown.phase === "paused" ? "timerPaused" : "timerAccent",
                progress: () => root.countdown.progress,
                open: "timer"
            })
    }

    property Feed recordSaving: Feed {
        hub: root.statuses
        bus: root.events
        key: "recordSaving"
        on: (root.cfg.recordSaving ?? true) && (root.recorder?.saving ?? false)
        entry: ({ priority: 80, color: "accentRed", progress: null, open: "" })
        event: ({ icon: "", color: "accentRed", text: I18n.tr("Saving recording") })
    }

    property Feed shazamListen: Feed {
        hub: root.statuses
        bus: root.events
        key: "shazam"
        on: (root.cfg.shazam ?? true) && root.shazam?.phase === "listening"
        entry: ({ priority: 70, color: "shazam", progress: null, open: "" })
    }

    property Feed transcription: Feed {
        hub: root.statuses
        bus: root.events
        key: "transcribe"
        on: (root.cfg.transcribe ?? true) && (root.transcribe?.busy ?? false)
        entry: ({
                priority: 60,
                color: "qsIndigo",
                progress: () => root.transcribe.stage === "loading" ? null : root.transcribe.progress,
                open: "transcript"
            })
    }

    property Feed localSending: Feed {
        hub: root.statuses
        bus: root.events
        key: "localSend"
        on: (root.cfg.localSend ?? true) && (root.localSend?.phase === "sending" || (root.localSend?.transferring ?? false))
        entry: ({
                priority: 50,
                color: "qsBlue",
                progress: () => root.localSend.transferring ? root.localSend.progress : null,
                open: "stash"
            })
        event: ({
                glyph: "transfer",
                glyphArgs: { progress: null },
                icon: "",
                color: "qsBlue",
                text: root.localSend?.transferring ? I18n.tr("Receiving files") : I18n.tr("Sending files")
            })
    }

    property Feed wallpaperIndex: Feed {
        hub: root.statuses
        bus: root.events
        key: "wallpaperIndex"
        on: (root.cfg.wallpaperIndex ?? true) && (root.semantic?.indexing ?? false)
        entry: ({
                priority: 10,
                color: "focusPurple",
                progress: () => root.semantic.total > 0 ? root.semantic.done / root.semantic.total : null,
                open: ""
            })
        event: ({ icon: "", color: "focusPurple", text: I18n.tr("Indexing wallpapers") })
    }
}
