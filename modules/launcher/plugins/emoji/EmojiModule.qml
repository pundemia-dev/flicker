import QtQuick
import Quickshell
import Quickshell.Io
import "../../api"
import "../../../../components"
import "../../../../config"
import "EmojiData.js" as Data

// Emoji & symbols (`!emoji`): a grid body in place of the list. Category
// tabs on top (recent, the Unicode emoji groups, then symbol groups —
// punctuation, arrows, math, currency, keys, …), the grid, a footer with
// the current character's name. The search field searches everything (en +
// ru names and CLDR keywords). Enter / click = TYPE it into the window the
// launcher was opened over (services/TextTyper = the dictation wtype path,
// after the island released the keyboard); Alt+Enter = copy instead.
// Keys: arrows walk the grid, Tab / Shift+Tab = category, PgUp/PgDn = page.
// Data: emoji.tsv (scripts/launcher/gen_emoji_data.py), parsed once per
// shell (EmojiData.js); recents in statePath emoji-recents.json.
LauncherPlugin {
    id: root

    readonly property var ecfg: root.cfg?.emoji ?? ({})
    readonly property string recentId: "__recent__"
    property string query: ""
    property string group: ""
    property var filtered: []
    property int current: 0
    // Bumped on every rebuild: cells created right after it grow in as a
    // wave, cells created later by scrolling just appear.
    property real revealStamp: 0
    property var recents: []
    property bool dataReady: Data.loaded()

    // No rows: the body is the whole UI.
    ScriptModel {
        id: noRows
        values: []
    }
    listModel: noRows
    bodyComponent: bodyComp
    bodyWidth: root.cfg?.width ?? 620
    // The list's own cap (LauncherMetrics.maxListHeight): no new reserve.
    bodyHeight: (root.cfg?.maxShown ?? 6) * (root.cfg?.itemHeight ?? 60) + ((root.cfg?.maxShown ?? 6) - 1) * (root.cfg?.itemSpacing ?? 5)

    readonly property real tabsH: 32
    readonly property real footerH: 40
    readonly property real gap: 8
    readonly property real cell: root.ecfg.cellSize ?? 50
    readonly property int columns: Math.max(1, Math.floor(root.bodyWidth / root.cell))
    readonly property int pageRows: Math.max(1, Math.floor((root.bodyHeight - root.tabsH - root.footerH - root.gap * 2) / root.cell))

    readonly property var tabs: {
        if (!root.dataReady)
            return [];
        const out = [];
        if (root.recents.length > 0)
            out.push({ id: root.recentId, glyph: "", icon: true, name: I18n.tr("Recently used") });
        for (const g of Data.groupList())
            out.push({ id: g, glyph: Data.glyph(g), icon: false, name: I18n.tr(g) });
        return out;
    }
    // Hover selects (session menu): the footer always shows `current`.
    readonly property var shown: root.current >= 0 && root.current < root.filtered.length ? root.filtered[root.current] : null

    FileView {
        id: dataFile
        path: Qt.resolvedUrl("emoji.tsv")
        // Parsed once per shell: later instances skip the read.
        preload: !Data.loaded()
        blockLoading: true
        printErrors: false
        onLoaded: {
            Data.load(dataFile.text());
            root.dataReady = true;
        }
        onLoadFailed: err => console.warn("[Emoji] emoji.tsv:", err)
    }

    FileView {
        id: recentsFile
        path: Quickshell.statePath("emoji-recents.json")
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const a = JSON.parse(recentsFile.text());
                root.recents = Array.isArray(a) ? a.filter(c => typeof c === "string") : [];
            } catch (e) {
                root.recents = [];
            }
        }
    }

    // The data can land after onActivated (first open in this shell).
    onDataReadyChanged: {
        if (!root.isActive)
            return;
        if (root.group === "")
            root.group = root.defaultGroup();
        root.rebuild();
    }

    function defaultGroup(): string {
        return root.recents.length > 0 ? root.recentId : (Data.groupList()[0] ?? "");
    }

    function onActivated(initialQuery: string): void {
        root.group = root.defaultGroup();
        root.query = (initialQuery ?? "").trim();
        root.rebuild();
    }

    function handleInput(q: string): void {
        root.query = q ?? "";
        root.rebuild();
    }

    function rebuild(): void {
        root.revealStamp = Date.now();
        if (root.query.trim() !== "")
            root.filtered = Data.search(root.query);
        else if (root.group === root.recentId)
            root.filtered = Data.lookup(root.recents);
        else
            root.filtered = Data.inGroup(root.group);
        root.current = root.filtered.length > 0 ? 0 : -1;
    }

    function setGroup(id: string): void {
        root.group = id;
        if (root.query !== "") {
            root.query = "";
            root.requestSetInput("");
        }
        root.rebuild();
    }

    function stepGroup(d: int): void {
        const ids = root.tabs.map(t => t.id);
        if (ids.length === 0)
            return;
        const i = root.query.trim() !== "" ? (d > 0 ? -1 : 0) : ids.indexOf(root.group);
        root.setGroup(ids[(Math.max(i, -1) + d + ids.length) % ids.length]);
    }

    function move(d: int): void {
        const n = root.filtered.length;
        if (n === 0)
            return;
        root.current = Math.max(0, Math.min(n - 1, root.current + d));
    }

    function remember(ch: string): void {
        const limit = root.ecfg.recentsLimit ?? 48;
        root.recents = [ch].concat(root.recents.filter(c => c !== ch)).slice(0, limit);
        recentsFile.setText(JSON.stringify(root.recents));
    }

    // Type (default) or copy (alt) the character, close the launcher.
    function pick(r: var, copy: bool): void {
        if (!r)
            return;
        root.remember(r.ch);
        const typer = root.host?.typer ?? null;
        if (copy || !typer) {
            const q = "'" + r.ch.replace(/'/g, "'\\''") + "'";
            Quickshell.execDetached(["sh", "-c", `printf %s ${q} | wl-copy`]);
        } else {
            typer.typeLater(r.ch, root.ecfg.typeDelayMs ?? 150);
        }
        root.requestClose(true);
    }

    function handleKey(event: var): bool {
        switch (event.key) {
        case Qt.Key_Left:
            root.move(-1);
            return true;
        case Qt.Key_Right:
            root.move(1);
            return true;
        case Qt.Key_Up:
            root.move(-root.columns);
            return true;
        case Qt.Key_Down:
            root.move(root.columns);
            return true;
        case Qt.Key_PageUp:
            root.move(-root.columns * root.pageRows);
            return true;
        case Qt.Key_PageDown:
            root.move(root.columns * root.pageRows);
            return true;
        case Qt.Key_Tab:
            root.stepGroup(1);
            return true;
        case Qt.Key_Backtab:
            root.stepGroup(-1);
            return true;
        }
        return false;
    }

    function handleExecute(query: string, isAlt: bool): bool {
        root.pick(root.filtered[root.current] ?? null, isAlt);
        return true;
    }

    function displayName(r: var): string {
        if (!r)
            return "";
        return I18n.lang === "ru" && r.ru !== "" ? r.ru : r.name;
    }

    // Motion (session menu style): ONE flat selection plate (Theme.sessionPlate)
    // springing to the selected cell, stretched along its flight
    // (VelocityDeform on the slot in grid CONTENT coords, so a scroll does
    // not stretch it); hover selects; the selected glyph grows, a press
    // shrinks it. The tab bar has its own plate. A new set (tab / search)
    // grows in as a diagonal wave, the plate pops in at the first cell;
    // keyboard scrolling glides (spring on contentY).
    Component {
        id: bodyComp
        Item {
            id: body

            readonly property color plateColor: root.theme.sessionPlate ?? "#242426"
            readonly property real idleOpacity: 0.55

            // ── Category tabs ──────────────────────────────────────────
            Item {
                id: tabBar
                width: parent.width
                height: root.tabsH
                readonly property real tabW: root.tabs.length > 0 ? width / root.tabs.length : 0
                readonly property int activeIndex: root.query.trim() !== "" ? -1 : root.tabs.findIndex(t => t.id === root.group)
                // The plate stays where it was while a search hides it.
                property int plateIndex: Math.max(0, activeIndex)
                onActiveIndexChanged: if (activeIndex >= 0) plateIndex = activeIndex

                Rectangle {
                    id: tabPlate
                    readonly property real size: Math.min(tabBar.tabW - 2, root.tabsH)
                    transform: VelocityDeform {
                        item: tabPlate
                        useSource: true
                        sourceX: tabPlate.x + tabPlate.width / 2
                        sizeW: tabPlate.size
                        sizeH: tabPlate.size
                    }
                    x: tabBar.plateIndex * tabBar.tabW + (tabBar.tabW - size) / 2
                    Behavior on x { Spring {} }
                    width: size
                    height: root.tabsH
                    radius: height / 2
                    color: body.plateColor
                    opacity: tabBar.activeIndex >= 0 ? 1 : 0
                    scale: tabBar.activeIndex >= 0 ? 1 : 0.6
                    Behavior on opacity { Spring { eps: 0.01 } }
                    Behavior on scale { Spring { stiffness: 6; damp: 0.45; eps: 0.002 } }
                }

                Row {
                    Repeater {
                        model: root.tabs
                        Item {
                            id: tab
                            required property var modelData
                            required property int index
                            readonly property bool active: tabBar.activeIndex === index
                            width: tabBar.tabW
                            height: tabBar.height

                            Text {
                                anchors.centerIn: parent
                                text: tab.modelData.glyph
                                color: root.theme.islandFg
                                font.family: tab.modelData.icon ? root.theme.iconFamily
                                    : (Data.EMOJI_GROUPS.indexOf(tab.modelData.id) >= 0 ? "Noto Color Emoji" : root.theme.fontFamily)
                                font.pixelSize: tab.modelData.icon ? 17 : 16
                                property real ink: tab.active ? 1 : (tabMa.containsMouse ? 0.85 : body.idleOpacity)
                                Behavior on ink { Spring { stiffness: 4; damp: 0.7; eps: 0.005 } }
                                opacity: ink
                                property real base: tabMa.pressed ? 0.8 : tab.active ? 1 : (tabMa.containsMouse ? 0.97 : 0.88)
                                Behavior on base { Spring { stiffness: 6; damp: 0.45; eps: 0.002 } }
                                scale: base
                            }
                            MouseArea {
                                id: tabMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.setGroup(tab.modelData.id)
                            }
                        }
                    }
                }
            }

            // ── Grid ───────────────────────────────────────────────────
            GridView {
                id: grid
                y: root.tabsH + root.gap
                width: parent.width
                height: parent.height - y - root.gap - root.footerH
                clip: true
                cellWidth: width / root.columns
                cellHeight: root.cell
                model: root.filtered
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: root.cell * 4

                // Target slot of the selection, content coords.
                readonly property real slotX: Math.max(0, root.current) % root.columns * cellWidth
                readonly property real slotY: Math.floor(Math.max(0, root.current) / root.columns) * cellHeight
                onSlotYChanged: grid.ensureVisible()
                property bool snap: false

                function ensureVisible(): void {
                    if (root.current < 0)
                        return;
                    const cur = scrollAnim.running ? scrollAnim.to : grid.contentY;
                    let to = cur;
                    if (grid.slotY < cur)
                        to = grid.slotY;
                    else if (grid.slotY + grid.cellHeight > cur + grid.height)
                        to = grid.slotY + grid.cellHeight - grid.height;
                    to = Math.max(0, Math.min(to, Math.max(0, grid.contentHeight - grid.height)));
                    if (Math.abs(to - cur) < 0.5)
                        return;
                    scrollAnim.to = to;
                    scrollAnim.restart();
                }

                SpringAnimation {
                    id: scrollAnim
                    target: grid
                    property: "contentY"
                    spring: 3
                    damping: 0.5
                    epsilon: 0.25
                }

                // New set: back to the top, the plate snaps to cell 0 and
                // pops in (no flight across the old content).
                Connections {
                    target: root
                    function onRevealStampChanged(): void {
                        scrollAnim.stop();
                        grid.snap = true;
                        grid.contentY = 0;
                        plate.appear = 0;
                        Qt.callLater(() => {
                            grid.snap = false;
                            plate.appear = 1;
                        });
                    }
                }

                // In the contentItem (scrolls with the cells) — a child
                // declared in a GridView is NOT put there by itself, unlike
                // a Flickable's. Under the delegates (z).
                Rectangle {
                    id: plate
                    parent: grid.contentItem
                    z: -1
                    property real appear: 1
                    Behavior on appear { Spring { stiffness: 5; damp: 0.45; eps: 0.004 } }
                    transform: VelocityDeform {
                        item: plate
                        active: plate.visible && !grid.snap
                        useSource: true
                        sourceX: plate.x + plate.width / 2
                        sourceY: plate.y + plate.height / 2
                        sizeW: grid.cellHeight
                        sizeH: grid.cellHeight
                    }
                    x: grid.slotX + 2
                    y: grid.slotY + 2
                    Behavior on x { enabled: !grid.snap; Spring {} }
                    Behavior on y { enabled: !grid.snap; Spring {} }
                    width: grid.cellWidth - 4
                    height: grid.cellHeight - 4
                    radius: Math.min(width, height) * 0.32
                    color: body.plateColor
                    visible: root.current >= 0
                    opacity: Math.max(0, Math.min(1, appear))
                    scale: 0.5 + 0.5 * appear
                }

                delegate: Item {
                    id: cellItem
                    required property var modelData
                    required property int index
                    readonly property bool selected: index === root.current
                    width: grid.cellWidth
                    height: grid.cellHeight

                    // Wave: cells built right after a rebuild grow in, later
                    // ones (scrolled into view) are just there.
                    property real appear: 1
                    property bool animated: false
                    Behavior on appear { enabled: cellItem.animated; Spring { stiffness: 4.5; damp: 0.42; eps: 0.004 } }
                    Timer {
                        id: appearDelay
                        onTriggered: cellItem.appear = 1
                    }
                    Component.onCompleted: {
                        if (Date.now() - root.revealStamp > 200)
                            return;
                        cellItem.appear = 0;
                        cellItem.animated = true;
                        const col = cellItem.index % root.columns, row = Math.floor(cellItem.index / root.columns);
                        appearDelay.interval = Math.min(360, (col + row * 1.5) * 13);
                        appearDelay.start();
                    }

                    Text {
                        anchors.centerIn: parent
                        text: cellItem.modelData.ch
                        color: root.theme.islandFg
                        font.family: cellItem.modelData.emoji ? "Noto Color Emoji" : root.theme.fontFamily
                        font.pixelSize: cellItem.modelData.emoji ? 26 : 22
                        // Symbols are ink: dimmed until selected (emoji keep
                        // their colours).
                        property real ink: cellItem.modelData.emoji || cellItem.selected ? 1 : 0.7
                        Behavior on ink { Spring { stiffness: 4; damp: 0.7; eps: 0.005 } }
                        opacity: ink * Math.max(0, Math.min(1, cellItem.appear))
                        property real base: cellMa.pressed ? 0.82 : cellItem.selected ? 1.14 : 1
                        Behavior on base { Spring { stiffness: 6; damp: 0.45; eps: 0.002 } }
                        scale: base * (0.4 + 0.6 * cellItem.appear)
                    }
                    MouseArea {
                        id: cellMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        // Real pointer motion only: cells gliding under a
                        // resting pointer (keyboard scroll) never steal it.
                        onPositionChanged: if (!scrollAnim.running) root.current = cellItem.index
                        onPressed: root.current = cellItem.index
                        onClicked: mouse => root.pick(cellItem.modelData, (mouse.modifiers & Qt.AltModifier) !== 0)
                    }
                }
            }

            Text {
                anchors.centerIn: grid
                text: root.query.trim() !== "" ? I18n.tr("Nothing found") : I18n.tr("Nothing here yet")
                color: root.theme.cardDim
                font.family: root.theme.fontFamily
                font.pixelSize: root.cfg?.fontSize ?? 16
                opacity: root.filtered.length === 0 ? 1 : 0
                Behavior on opacity { Spring { eps: 0.01 } }
            }

            // ── Footer: the current character ──────────────────────────
            GlyphBump {
                id: bump
                peak: 1.25
            }
            Connections {
                target: root
                function onShownChanged(): void {
                    if (root.shown)
                        bump.bump();
                }
            }
            Item {
                anchors.bottom: parent.bottom
                width: parent.width
                height: root.footerH

                Text {
                    id: big
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.footerH
                    horizontalAlignment: Text.AlignHCenter
                    text: root.shown?.ch ?? ""
                    color: root.theme.islandFg
                    font.family: root.shown?.emoji ? "Noto Color Emoji" : root.theme.fontFamily
                    font.pixelSize: 28
                    scale: bump.value
                }
                Column {
                    anchors.left: big.right
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                        width: parent.width
                        text: root.shown ? root.displayName(root.shown) : I18n.tr("Search emoji and symbols")
                        color: root.theme.islandFg
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.cfg?.subFontSize ?? 14
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: I18n.tr("Enter — type · Alt+Enter — copy · Tab — category")
                        color: root.theme.cardDim
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.fontSizeTiny + 1
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
