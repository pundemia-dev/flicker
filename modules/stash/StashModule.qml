import QtQuick

// Stash (pShell file tray + LocalSend port) as an island module. Opened
// over IPC only (`island stash`); the drop chooser is StashDropModule.
// payload.view: "tray" | "send" (device picker) | "incoming" (accept card)
// | "transcript" (WhisperX text of payload.file, TranscriptView)
// | "preview" (Quick Look of payload.file, StashPreview; ← / → step through
// the tray, each step a module re-open = blur swap + island refit).
// Keyboard (Exclusive while the tray / preview shows): forwarded to the
// view's handleKey; unhandled Esc closes.
// View changes go through Island.openModule (openRequested), so each one
// replays the ContentSwap and the island resizes (StashMetrics).
// payload.returnView === "tray": the flow started from the tray and goes
// back there when finished, otherwise the module closes.
Item {
    id: root
    required property var payload
    required property var stash
    required property var localSend
    required property var cfg
    required property var theme
    required property real surfaceRadius
    signal closeRequested
    signal openRequested(string name, var payload)

    readonly property string view: root.payload?.view ?? "tray"
    readonly property real tileRadius: Math.max(4, root.surfaceRadius - root.cfg.padding)
    readonly property bool wantsKeyboard: root.view === "tray" || root.view === "preview"

    focus: true
    Component.onCompleted: root.forceActiveFocus()
    Keys.onPressed: event => {
        const v = root.view === "tray" ? tray : root.view === "preview" ? previewLoader.item : null;
        if (v?.handleKey(event)) {
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            event.accepted = true;
            root.closeRequested();
        }
    }

    function openPreview(file: string): void {
        root.openRequested("stash", { view: "preview", file: file, returnView: "tray" });
    }
    // ← / → in Quick Look: neighbours in tray order, wrapping round.
    function stepPreview(delta: int): void {
        const all = root.stash.allPaths();
        if (all.length < 2)
            return;
        const i = all.indexOf(root.payload?.file ?? "");
        root.openPreview(all[((i < 0 ? 0 : i + delta) % all.length + all.length) % all.length]);
    }

    function finish(): void {
        if ((root.payload?.returnView ?? "") === "tray")
            root.openRequested("stash", { view: "tray" });
        else
            root.closeRequested();
    }

    function startSend(files: var): void {
        if (!root.localSend.start(files))
            return;
        root.openRequested("stash", { view: "send", returnView: "tray" });
    }

    // Tile button: queue the file (no-op when already done / queued) and
    // show its transcript view; leaving it keeps the run going.
    function openTranscript(file: string): void {
        root.stash.transcribe.request(file);
        root.openRequested("stash", { view: "transcript", file: file, returnView: "tray" });
    }

    // The tray rescans while it is on screen.
    Binding {
        target: root.stash
        property: "watching"
        value: root.view === "tray"
    }

    // Set while the module is being torn down: cancel() below flips the
    // phase to idle, which must not re-open anything from a dying module.
    property bool closing: false

    Connections {
        target: root.localSend
        enabled: !root.closing
        // Upload finished (or failed: send.py notifies) → leave the picker.
        function onPhaseChanged(): void {
            if (root.view === "send" && root.localSend.phase === "idle")
                root.finish();
        }
        // Card resolved: accepted files land in the tray, a reject closes.
        function onHasIncomingChanged(): void {
            if (root.view === "incoming" && !root.localSend.hasIncoming)
                root.acceptedOnce ? root.openRequested("stash", { view: "tray" }) : root.finish();
        }
        // The next queued request starts undecided.
        function onRequestArrived(): void {
            root.acceptedOnce = false;
        }
        function onTransferringChanged(): void {
            if (root.localSend.transferring)
                root.acceptedOnce = true;
        }
    }
    property bool acceptedOnce: false

    // Debug IPC hook (island stashMenu <i>).
    function debugMenu(i: int): void {
        tray.debugMenu(i);
    }

    // Picker dismissed (swipe-up / IPC close) before a target was picked.
    Component.onDestruction: {
        root.closing = true;
        root.stash.watching = false;
        root.localSend.cancel();
    }

    Item {
        anchors.fill: parent
        anchors.margins: root.cfg.padding

        StashTray {
            id: tray
            anchors.fill: parent
            visible: root.view === "tray"
            stash: root.stash
            localSend: root.localSend
            cfg: root.cfg
            theme: root.theme
            tileRadius: root.tileRadius
            onSendRequested: files => root.startSend(files)
            onTranscribeRequested: file => root.openTranscript(file)
            onPreviewRequested: file => root.openPreview(file)
        }

        Loader {
            id: previewLoader
            anchors.fill: parent
            active: root.view === "preview"
            sourceComponent: StashPreview {
                path: root.payload?.file ?? ""
                stash: root.stash
                cfg: root.cfg
                theme: root.theme
                onBack: root.finish()
                onStep: delta => root.stepPreview(delta)
            }
        }

        Loader {
            anchors.fill: parent
            active: root.view === "transcript"
            sourceComponent: TranscriptView {
                path: root.payload?.file ?? ""
                stash: root.stash
                cfg: root.cfg
                theme: root.theme
                onBack: root.finish()
                onCloseRequested: root.closeRequested()
            }
        }

        DevicePicker {
            anchors.fill: parent
            visible: root.view === "send"
            localSend: root.localSend
            cfg: root.cfg
            theme: root.theme
            tileRadius: root.tileRadius
        }

        Loader {
            anchors.fill: parent
            active: root.view === "incoming" && root.localSend.hasIncoming
            sourceComponent: IncomingRequest {
                localSend: root.localSend
                stash: root.stash
                cfg: root.cfg
                theme: root.theme
            }
        }
    }
}
