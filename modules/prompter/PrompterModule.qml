import QtQuick
import "../../components"
import "../../config"

// Teleprompter in the island (services/Prompter owns text, cursor, mode).
// Pictures ("img" blocks) are not in the text: while one is current
// (Prompter.imageBlock) the island grows by cfg.imagePanelWidth and the
// panel on the right shows it.
// The script scrolls so the next word to read sits on the reading line
// (cfg.readLine of the viewport, marked by a thin bar on the left); read
// words dim, the next one is white. Footer: state (tap = pause) · mode
// (tap = cycle) · progress. Wheel = nudge the cursor by cfg.wheelWords.
// Keys after a click (OnDemand focus): Space pause, ↑/↓ nudge, PgUp/PgDn
// blocks, M mode, Esc close. Press-transparent apart from the footer pills
// (the swipe-up close lives under the module).
Item {
    id: root

    property var prompter: null
    property var theme: null
    property var cfg: null
    signal closeRequested

    readonly property var colors: ({
            read: root.theme.prompterRead.toString(),
            current: root.theme.prompterCurrent.toString(),
            ahead: root.theme.prompterAhead.toString(),
            note: root.theme.prompterNote.toString(),
            noteRead: root.theme.prompterNoteRead.toString(),
            mono: root.theme.monoFamily,
            hl: {
                default: root.theme.prompterHlDefault.toString(),
                red: root.theme.prompterHlRed.toString(),
                orange: root.theme.prompterHlOrange.toString(),
                yellow: root.theme.prompterHlYellow.toString(),
                green: root.theme.prompterHlGreen.toString(),
                blue: root.theme.prompterHlBlue.toString(),
                purple: root.theme.prompterHlPurple.toString()
            },
            hlAlpha: root.cfg?.highlightAlpha ?? 0.35,
            hlReadAlpha: root.cfg?.highlightReadAlpha ?? 0.14
        })
    readonly property real pad: root.cfg?.padding ?? 26
    readonly property real lineH: Math.round((root.cfg?.fontSize ?? 28) * (root.cfg?.lineHeight ?? 1.18))
    // Text column width from cfg, not the live island: the island grows by
    // the image panel (and animates on open) — the text must not re-wrap.
    readonly property real textW: (root.cfg?.width ?? 760) - root.pad * 2

    focus: true
    Keys.onEscapePressed: root.closeRequested()
    Keys.onPressed: event => {
        const p = root.prompter;
        const step = root.cfg?.wheelWords ?? 4;
        if (event.key === Qt.Key_Space)
            p.togglePause();
        else if (event.key === Qt.Key_Down)
            p.moveBy(step * 2);
        else if (event.key === Qt.Key_Up)
            p.moveBy(-step * 2);
        else if (event.key === Qt.Key_PageDown)
            p.jumpBlock(1);
        else if (event.key === Qt.Key_PageUp)
            p.jumpBlock(-1);
        else if (event.key === Qt.Key_M)
            p.cycleMode();
        else
            return;
        event.accepted = true;
    }
    // Focus for the keys; a passive tap never steals the swipe-up press.
    TapHandler {
        onTapped: root.forceActiveFocus()
    }

    Item {
        id: viewport
        x: root.pad
        y: root.pad * 0.6
        width: root.textW
        height: root.height - y - (root.cfg?.footerHeight ?? 26) - root.pad * 0.4
        clip: true

        Column {
            id: column
            width: viewport.width
            spacing: root.cfg?.blockGap ?? 14
            transform: Translate { y: -scroller.pos }
            // Layout change (re-wrap): snap back onto the
            // reading line, no spring ride from the shifted position.
            onHeightChanged: {
                scroller.instant = true;
                scroller.refresh();
            }

            Repeater {
                id: blocks
                model: root.prompter?.doc.blocks ?? []
                delegate: Loader {
                    required property var modelData
                    width: column.width
                    // Pictures live in the side panel: no slot in the column.
                    visible: modelData.kind !== "img"
                    sourceComponent: modelData.kind === "hr" ? hrComp : (modelData.kind === "img" ? null : textComp)
                    Component {
                        id: textComp
                        PrompterBlock {
                            width: column.width
                            block: modelData
                            cursor: root.prompter.cursor
                            colors: root.colors
                            cfg: root.cfg
                            family: root.theme.fontFamily
                        }
                    }
                    Component {
                        id: hrComp
                        Item {
                            width: column.width
                            height: root.lineH * 0.6
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width * 0.3
                                height: 1
                                color: root.theme.prompterRead
                            }
                        }
                    }
                }
            }
        }

        WheelHandlerArea {
            anchors.fill: parent
        }
    }

    // Scroll position: the cursor word's line on the reading line.
    Item {
        id: scroller
        visible: false
        property real pos: 0
        property bool instant: true
        Behavior on pos {
            enabled: !scroller.instant
            Spring {
                stiffness: root.cfg?.scrollSpring ?? 2.4
                damp: root.cfg?.scrollDamping ?? 0.42
                eps: 0.5
            }
        }
        function refresh(): void {
            Qt.callLater(scroller.apply);
        }
        function apply(): void {
            const p = root.prompter;
            const words = p?.doc.words ?? [];
            const all = p?.doc.blocks ?? [];
            if (all.length === 0)
                return;
            let y;
            if (p.cursor >= words.length) {
                let li = all.length - 1;
                while (li > 0 && all[li].kind === "img")
                    li--;
                const last = blocks.itemAt(li);
                y = last ? last.y + last.height - root.lineH / 2 : 0;
            } else {
                const bi = words[p.cursor].block;
                const holder = blocks.itemAt(bi);
                const item = holder?.item;
                if (!holder || !item || typeof item.wordRect !== "function")
                    return;
                const r = item.wordRect(p.cursor);
                y = holder.y + r.y + r.height / 2;
            }
            scroller.pos = y - viewport.height * (root.cfg?.readLine ?? 0.34);
            scroller.instant = false;
        }
    }
    Connections {
        target: root.prompter
        function onCursorChanged() { scroller.refresh(); }
        function onDocChanged() {
            scroller.instant = true;
            scroller.refresh();
        }
    }
    onWidthChanged: scroller.refresh()
    Component.onCompleted: scroller.refresh()

    // Reading line marker.
    Rectangle {
        x: (root.pad - width) / 2
        y: viewport.y + viewport.height * (root.cfg?.readLine ?? 0.34) - height / 2
        width: root.cfg?.markerWidth ?? 3
        height: root.lineH * 0.8
        radius: width / 2
        color: root.theme.prompterMarker
        opacity: root.prompter?.voiceState === "lost" ? 0.25 : (root.prompter?.paused ? 0.15 : 0.85)
        Behavior on opacity { NumberAnimation { duration: 250 } }
    }

    // Empty state.
    Text {
        anchors.centerIn: viewport
        width: viewport.width
        visible: root.prompter?.empty ?? true
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        color: root.theme.subtleFg
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.fontSizeClock
        text: (root.prompter?.lastError ?? "").length > 0 ? root.prompter.lastError
            : I18n.tr("No script loaded. Pick a markdown file in the launcher (!prompt) or copy text and run: qs ipc call prompter clipboard")
    }

    // Footer: state · mode · progress.
    Item {
        id: footer
        x: root.pad
        width: root.textW
        height: root.cfg?.footerHeight ?? 26
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.pad * 0.4

        readonly property string stateText: {
            const p = root.prompter;
            if (!p)
                return "";
            if (p.paused)
                return I18n.tr("Paused");
            if (p.mode === "auto")
                return I18n.tr("%1 wpm").arg(root.cfg?.wpm ?? 130);
            if (p.mode === "manual")
                return I18n.tr("Scroll by hand");
            switch (p.voiceState) {
            case "starting":
                return I18n.tr("Starting…");
            case "listening":
                return I18n.tr("Listening · %1").arg(p.lang.toUpperCase());
            case "lost":
                return I18n.tr("Searching for your place…");
            case "error":
                return p.lastError.length > 0 ? p.lastError : I18n.tr("Microphone error");
            default:
                return I18n.tr("Microphone off");
            }
        }
        readonly property color dotColor: {
            const p = root.prompter;
            if (!p || p.paused || p.mode !== "voice")
                return root.theme.waveDim;
            if (p.voiceState === "listening")
                return root.theme.accentGreen;
            if (p.voiceState === "lost")
                return root.theme.accentYellow;
            if (p.voiceState === "error")
                return root.theme.accentRed;
            return root.theme.waveDim;
        }
        readonly property var modeNames: ({
                voice: I18n.tr("Voice"),
                auto: I18n.tr("Auto"),
                manual: I18n.tr("Manual")
            })

        FooterPill {
            id: statePill
            anchors.left: parent.left
            dot: footer.dotColor
            label: footer.stateText
            onClicked: root.prompter.togglePause()
        }
        FooterPill {
            anchors.left: statePill.right
            anchors.leftMargin: 6
            label: footer.modeNames[root.prompter?.mode ?? "voice"] ?? ""
            onClicked: root.prompter.cycleMode()
        }
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            color: root.theme.subtleFg
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fontSizeIndicator
            font.features: ({ "tnum": 1 })
            text: `${Math.round((root.prompter?.progress ?? 0) * 100)}%`
        }
    }

    component FooterPill: Rectangle {
        id: pill
        property color dot: "transparent"
        property string label: ""
        signal clicked
        anchors.verticalCenter: parent.verticalCenter
        height: footer.height - 4
        width: row.implicitWidth + 16
        radius: height / 2
        color: tap.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
        Behavior on width { Spring {} }
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 6
            Rectangle {
                visible: pill.dot.a > 0
                anchors.verticalCenter: parent.verticalCenter
                width: 6
                height: 6
                radius: 3
                color: pill.dot
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                color: root.theme.islandFg
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.fontSizeIndicator
                text: pill.label
            }
        }
        MouseArea {
            id: tap
            anchors.fill: parent
            hoverEnabled: true
            onClicked: pill.clicked()
        }
    }

    // Image panel right of the text: the current "img" block, latched while
    // the island shrinks back (fades out) and cross-faded between blocks.
    Item {
        id: panel
        readonly property int want: root.prompter?.imageBlock ?? -1
        property int shown: -1
        x: root.pad + root.textW + root.pad
        y: root.pad * 0.6
        width: (root.cfg?.imagePanelWidth ?? 440) - root.pad
        height: root.height - root.pad * 1.2
        opacity: 0

        function sync(): void {
            if (panel.want < 0) {
                swap.stop();
                hide.start();
            } else if (panel.want !== panel.shown || panel.opacity < 1) {
                hide.stop();
                swap.restart();
            }
        }
        onWantChanged: panel.sync()
        Component.onCompleted: {
            panel.shown = panel.want;
            panel.opacity = panel.want >= 0 ? 1 : 0;
        }
        Connections {
            target: root.prompter
            function onDocChanged() {
                // Same index, new doc (file edited / reopened): rebuild.
                panel.shown = -1;
                panel.sync();
            }
        }
        NumberAnimation {
            id: hide
            target: panel
            property: "opacity"
            to: 0
            duration: 200
        }
        SequentialAnimation {
            id: swap
            NumberAnimation {
                target: panel
                property: "opacity"
                to: 0
                duration: panel.shown >= 0 && panel.shown !== panel.want ? 120 : 0
            }
            ScriptAction {
                script: panel.shown = panel.want
            }
            NumberAnimation {
                target: panel
                property: "opacity"
                to: 1
                duration: 180
            }
        }

        ImageSet {
            anchors.fill: parent
            images: panel.shown >= 0 ? (root.prompter?.doc.blocks[panel.shown]?.images ?? []) : []
        }
    }

    // Pictures of one block fitted into the panel: one row at a common
    // height or one column at a common width, whichever draws them larger.
    // Each aspect is latched on its first load (sourceSize then follows the
    // drawn size, no reload loop); until then a square is assumed. A failed
    // one = its alt / file name.
    component ImageSet: Item {
        id: set
        property var images: []
        property var aspects: []
        readonly property real gap: 10
        readonly property real dpr: Screen.devicePixelRatio || 1
        onImagesChanged: set.aspects = []
        readonly property var rects: {
            const n = set.images.length;
            if (n === 0 || set.width <= 0 || set.height <= 0)
                return [];
            const a = [];
            for (let i = 0; i < n; i++)
                a.push(set.aspects[i] > 0 ? set.aspects[i] : 1);
            const g = set.gap * (n - 1);
            let sumA = 0, sumInv = 0;
            for (const v of a) {
                sumA += v;
                sumInv += 1 / v;
            }
            const rowH = Math.max(1, Math.min(set.height, (set.width - g) / sumA));
            const colW = Math.max(1, Math.min(set.width, (set.height - g) / sumInv));
            const rowArea = a.reduce((s, v) => s + v * rowH * rowH, 0);
            const colArea = a.reduce((s, v) => s + colW * colW / v, 0);
            const out = [];
            if (rowArea >= colArea) {
                let x = (set.width - (sumA * rowH + g)) / 2;
                for (const v of a) {
                    out.push(Qt.rect(Math.round(x), Math.round((set.height - rowH) / 2), Math.round(v * rowH), Math.round(rowH)));
                    x += v * rowH + set.gap;
                }
            } else {
                let y = (set.height - (sumInv * colW + g)) / 2;
                for (const v of a) {
                    out.push(Qt.rect(Math.round((set.width - colW) / 2), Math.round(y), Math.round(colW), Math.round(colW / v)));
                    y += colW / v + set.gap;
                }
            }
            return out;
        }
        function setAspect(i: int, a: real): void {
            const c = set.aspects.slice();
            c[i] = a;
            set.aspects = c;
        }

        Repeater {
            model: set.images
            delegate: Item {
                id: cell
                required property var modelData
                required property int index
                readonly property rect r: set.rects[cell.index] ?? Qt.rect(0, 0, 0, 0)
                readonly property bool latched: set.aspects[cell.index] > 0
                x: cell.r.x
                y: cell.r.y
                width: cell.r.width
                height: cell.r.height

                Image {
                    id: pic
                    anchors.fill: parent
                    source: cell.modelData.src
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                    sourceSize.width: cell.latched ? Math.ceil(cell.width * set.dpr) : 0
                    onStatusChanged: {
                        if (cell.latched)
                            return;
                        if (pic.status === Image.Ready && pic.implicitHeight > 0)
                            set.setAspect(cell.index, pic.implicitWidth / pic.implicitHeight);
                        else if (pic.status === Image.Error)
                            set.setAspect(cell.index, 1.6);
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    visible: pic.status === Image.Error
                    radius: 10
                    color: Qt.rgba(1, 1, 1, 0.06)
                    Text {
                        anchors.fill: parent
                        anchors.margins: 8
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        color: root.theme.prompterNote
                        font.family: root.theme.fontFamily
                        font.italic: true
                        font.pixelSize: Math.round((root.cfg?.fontSize ?? 28) * (root.cfg?.noteScale ?? 0.78))
                        text: cell.modelData.alt
                    }
                }
            }
        }
    }

    // Wheel = nudge the cursor (accumulated: touchpads send small deltas).
    component WheelHandlerArea: MouseArea {
        property real acc: 0
        acceptedButtons: Qt.NoButton
        onWheel: wheel => {
            const d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.pixelDelta.y * 4;
            acc += d;
            const steps = Math.trunc(acc / 120);
            if (steps !== 0) {
                acc -= steps * 120;
                root.prompter.moveBy(-steps * (root.cfg?.wheelWords ?? 4));
            }
            wheel.accepted = true;
        }
    }
}
