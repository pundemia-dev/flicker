import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "../../api"
import "../../../../components"
import "../../../../config"

// GIF search in the launcher (`!gif`): the search field is the query (empty
// = trending), the body is a grid of animated tiles. Backend
// scripts/gifs/search.py (GIPHY or Tenor, stdlib, IPv4): one process per
// page prints the page, then one line per downloaded preview — tiles fade
// in as their file lands (Qt's own network loader stalls on broken IPv6,
// so Qt only ever sees local files). API key from ai.keysFile
// ({"giphy": "..."} or {"tenor": "..."}), launcher.gifs.provider "auto"
// takes whichever is there (GIPHY first).
// Masonry body (own scroll, not a Flickable: press-transparency like
// LauncherList); tiles load / play only near / inside the view.
// Keys: arrows move between neighbours, Tab in result order, PageUp/PageDown
// by a screen, the wheel scrolls (hover selects), Enter = copy
// (launcher.gifs.copyAs: file = text/uri-list of the downloaded GIF —
// chats attach it, image = image/gif bytes, url = the link), Alt+Enter =
// the link, Ctrl+O = open the page in the browser. The copy runs detached:
// the plugin is destroyed with the launcher right after.
LauncherPlugin {
    id: root

    // Masonry: `columns` columns inside `inset` px from the island edges;
    // each GIF keeps its aspect (clamped to minAspect..maxAspect = h/w) and
    // goes into the shortest column. No footer: the selected tile lifts
    // (selectScale), its title sits on it, a blurred outline fading outward
    // surrounds it (see the focus rect below).
    readonly property var g: root.cfg?.gifs ?? ({})
    readonly property int columns: Math.max(2, root.g.columns ?? 3)
    readonly property real spacing: root.g.spacing ?? 12
    readonly property real inset: root.g.inset ?? 10
    readonly property real colW: (root.bodyWidth - root.inset * 2 - root.spacing * (root.columns - 1)) / root.columns
    readonly property real viewH: root.g.height ?? 380
    // Room above the first row for the lifted selection (the body clips).
    readonly property real topPad: root.spacing

    ScriptModel {
        id: noRows
        values: []
    }
    listModel: noRows
    bodyComponent: bodyComp
    bodyWidth: root.cfg?.width ?? 620
    bodyHeight: root.viewH

    // ── API key ───────────────────────────────────────────────────────
    readonly property string keysPath: {
        const p = (Config.data.ai?.keysFile ?? "~/.config/flicker/apikeys.json").trim();
        return p.startsWith("~/") ? `${Quickshell.env("HOME")}/${p.slice(2)}` : p;
    }
    property var keys: ({})
    property bool keysLoaded: false
    FileView {
        path: root.keysPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.keys = JSON.parse(text()) ?? {};
            } catch (e) {
                root.keys = {};
            }
            root.keysLoaded = true;
        }
        onLoadFailed: {
            root.keys = {};
            root.keysLoaded = true;
        }
    }
    readonly property string provider: {
        const want = root.g.provider ?? "auto";
        if (want !== "auto")
            return want;
        return root.keys.giphy ? "giphy" : (root.keys.tenor ? "tenor" : "");
    }
    readonly property string apiKey: root.provider ? (root.keys[root.provider] ?? "") : ""
    readonly property string providerName: root.provider === "tenor" ? "Tenor" : "GIPHY"
    onApiKeyChanged: if (root.isActive) root.search()

    readonly property string cacheDir: {
        const d = (root.g.cacheDir ?? "").trim();
        if (d !== "")
            return d.startsWith("~/") ? `${Quickshell.env("HOME")}/${d.slice(2)}` : d;
        return (Quickshell.env("XDG_CACHE_HOME") || `${Quickshell.env("HOME")}/.cache`) + "/flicker/gifs";
    }
    readonly property string script: `${Quickshell.shellDir}/scripts/gifs/search.py`

    // ── Results ───────────────────────────────────────────────────────
    ListModel {
        id: results
    }
    // id → row, for the "ready" lines.
    property var rowOf: ({})
    property int selected: 0
    property string query: ""
    property string next: ""
    property string error: ""
    property bool busy: false
    property int epoch: 0
    property var jobs: []
    // Layout: geo[i] = {x, y, h, col}; colItems[c] = indices top→bottom.
    property var geo: []
    property var colItems: []
    property var colH: []
    readonly property real contentH: root.colH.length ? Math.max(...root.colH) : 0
    property real scrollY: 0
    // Focus rect: springs to the selected tile. A blurred outline is drawn
    // around it (bandWidth px, blur falling off outward over bandSteps
    // nested rings: the selected GIF's own colours smear into the gaps and
    // the near edges of its neighbours soften, the rest stays sharp); the
    // other tiles are dimmed to dimOthers.
    readonly property var selGeo: root.geo[root.selected] ?? null
    property real focusL: root.selGeo ? root.selGeo.x : 0
    property real focusT: root.selGeo ? root.selGeo.y : 0
    property real focusH: root.selGeo ? root.selGeo.h : 0
    Behavior on focusL { Spring { stiffness: root.g.focusStiffness ?? 4; damp: root.g.focusDamping ?? 0.5; eps: 0.5 } }
    Behavior on focusT { Spring { stiffness: root.g.focusStiffness ?? 4; damp: root.g.focusDamping ?? 0.5; eps: 0.5 } }
    Behavior on focusH { Spring { stiffness: root.g.focusStiffness ?? 4; damp: root.g.focusDamping ?? 0.5; eps: 0.5 } }
    readonly property real focusX: root.focusL + root.colW / 2
    readonly property real focusY: root.focusT + root.focusH / 2

    readonly property var current: root.selected >= 0 && root.selected < results.count ? results.get(root.selected) : null

    function stopJobs(): void {
        for (const j of root.jobs) {
            j.running = false;
            j.destroy();
        }
        root.jobs = [];
    }

    function search(): void {
        debounce.stop();
        root.epoch++;
        root.stopJobs();
        results.clear();
        root.rowOf = {};
        root.geo = [];
        root.colItems = [];
        root.colH = [];
        root.selected = 0;
        root.scrollY = 0;
        root.next = "";
        root.error = "";
        root.busy = false;
        if (!root.apiKey)
            return;
        root.request("");
    }

    function loadMore(): void {
        if (root.busy || root.next === "" || !root.apiKey)
            return;
        root.request(root.next);
    }

    function request(offset: string): void {
        root.busy = true;
        const job = jobComp.createObject(root, {
            epoch: root.epoch,
            req: JSON.stringify({
                provider: root.provider,
                key: root.apiKey,
                query: root.query,
                offset: offset,
                limit: root.g.pageSize ?? 24,
                rating: root.g.rating ?? "pg-13",
                locale: root.g.locale || I18n.lang || "en",
                cacheDir: root.cacheDir,
                cacheDays: root.g.cacheDays ?? 3
            }) + "\n"
        });
        root.jobs = root.jobs.concat([job]);
        job.running = true;
    }

    function landed(job: var, line: string): void {
        if (job.epoch !== root.epoch)
            return;
        let msg = null;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (msg.page) {
            const map = root.rowOf;
            const geo = root.geo.slice(), cols = root.colItems.slice(), colH = root.colH.slice();
            for (let c = cols.length; c < root.columns; c++) {
                cols.push([]);
                colH.push(root.topPad);
            }
            const lo = root.g.minAspect ?? 0.5, hi = root.g.maxAspect ?? 1.6;
            for (const it of msg.page.items) {
                if (map[it.id] !== undefined)
                    continue; // trending pages overlap now and then
                let c = 0;
                for (let k = 1; k < colH.length; k++)
                    if (colH[k] < colH[c] - 0.5)
                        c = k;
                const aspect = Math.max(lo, Math.min(hi, (it.height || 1) / (it.width || 1)));
                const h = Math.round(root.colW * aspect);
                const i = results.count;
                const geoI = { x: root.inset + c * (root.colW + root.spacing), y: colH[c], h: h, col: c };
                geo.push(geoI);
                cols[c] = cols[c].concat([i]);
                colH[c] += h + root.spacing;
                map[it.id] = i;
                results.append({
                    gid: it.id,
                    title: it.title,
                    page: it.page,
                    url: it.url,
                    full: it.full,
                    preview: it.preview,
                    ready: false,
                    tx: geoI.x,
                    ty: geoI.y,
                    th: h
                });
            }
            root.geo = geo;
            root.colItems = cols;
            root.colH = colH;
            root.rowOf = map;
            root.next = msg.page.next ?? "";
            root.busy = false;
        } else if (msg.ready) {
            const i = root.rowOf[msg.ready];
            if (i !== undefined)
                results.setProperty(i, "ready", true);
        } else if (msg.error) {
            root.error = msg.error;
            root.busy = false;
        }
    }

    Component {
        id: jobComp
        Process {
            id: job
            property int epoch: 0
            property string req: ""
            command: ["python3", "-I", root.script]
            stdinEnabled: true
            onStarted: write(job.req)
            stdout: SplitParser {
                onRead: line => root.landed(job, line)
            }
            onExited: {
                if (job.epoch === root.epoch && root.busy)
                    root.busy = false;
                root.jobs = root.jobs.filter(j => j !== job);
                job.destroy();
            }
        }
    }

    Timer {
        id: debounce
        interval: root.g.debounceMs ?? 350
        onTriggered: root.search()
    }

    function select(i: int, scroll: bool): void {
        if (results.count === 0)
            return;
        root.selected = Math.max(0, Math.min(results.count - 1, i));
        if (scroll)
            root.reveal(root.selected);
        const gs = root.geo[root.selected];
        if (gs && gs.y + gs.h > root.contentH - root.viewH * 1.5)
            root.loadMore();
    }
    // Scroll so tile i is fully in view (with a spacing margin).
    function reveal(i: int): void {
        const gs = root.geo[i];
        if (!gs)
            return;
        let y = root.scrollY;
        if (gs.y < y)
            y = gs.y - root.spacing;
        else if (gs.y + gs.h > y + root.viewH)
            y = gs.y + gs.h - root.viewH + root.spacing;
        root.scrollTo(y);
    }
    function scrollTo(y: real): void {
        root.scrollY = Math.max(0, Math.min(Math.max(0, root.contentH - root.spacing - root.viewH), y));
        if (root.scrollY + root.viewH * 2 > root.contentH)
            root.loadMore();
    }
    // Tile in column c whose vertical centre is nearest to `centre`.
    function nearestIn(c: int, centre: real): int {
        const list = root.colItems[c] ?? [];
        let best = -1, bestD = Infinity;
        for (const i of list) {
            const d = Math.abs(root.geo[i].y + root.geo[i].h / 2 - centre);
            if (d < bestD) {
                bestD = d;
                best = i;
            }
        }
        return best;
    }
    function moveCol(dc: int): void {
        const gs = root.geo[root.selected];
        if (!gs)
            return;
        const c = gs.col + dc;
        if (c < 0 || c >= root.colItems.length)
            return;
        const i = root.nearestIn(c, gs.y + gs.h / 2);
        if (i >= 0)
            root.select(i, true);
    }
    function moveRow(dy: int): void {
        const gs = root.geo[root.selected];
        if (!gs)
            return;
        const list = root.colItems[gs.col];
        const p = list.indexOf(root.selected) + dy;
        if (p >= 0 && p < list.length)
            root.select(list[p], true);
        else if (dy > 0)
            root.loadMore();
    }
    function movePage(dir: int): void {
        const gs = root.geo[root.selected];
        if (!gs)
            return;
        const i = root.nearestIn(gs.col, gs.y + gs.h / 2 + dir * root.viewH);
        if (i >= 0)
            root.select(i, true);
    }

    // ── Copy ──────────────────────────────────────────────────────────
    function copy(item: var, asUrl: bool): void {
        if (!item)
            return;
        const mode = asUrl ? "url" : (root.g.copyAs ?? "file");
        const paste = (root.g.autoPaste ?? false) ? (root.cfg?.clipboard?.pasteCommand ?? "wtype -M ctrl v -m ctrl") : "";
        // $1 url to fetch, $2 cache dir, $3 mode, $4 page/link, $5 paste cmd.
        const sh = 'set -e; '
            + 'if [ "$3" = url ]; then printf %s "$4" | wl-copy; else '
            + 'f=$(python3 -I "$0" fetch "$1" "$2"); '
            + 'if [ "$3" = image ]; then wl-copy --type image/gif < "$f"; '
            + 'else printf "file://%s\\r\\n" "$f" | wl-copy --type text/uri-list; fi; fi; '
            + '[ -n "$5" ] && { sleep 0.06; sh -c "$5"; } || true';
        Quickshell.execDetached(["sh", "-c", sh, root.script, item.full, root.cacheDir, mode,
            (root.g.linkKind ?? "gif") === "page" && item.page ? item.page : item.full, paste]);
        root.requestClose(true);
    }

    // ── LauncherPlugin hooks ──────────────────────────────────────────
    function onActivated(initialQuery: string): void {
        root.query = (initialQuery ?? "").trim();
        root.search();
    }
    function onDeactivated(): void {
        debounce.stop();
        root.epoch++;
        root.stopJobs();
    }
    function handleInput(q: string): void {
        const t = (q ?? "").trim();
        if (t === root.query)
            return;
        root.query = t;
        debounce.restart();
    }
    function handleKey(event: var): bool {
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        switch (event.key) {
        case Qt.Key_Left:
            if (ctrl)
                return false;
            root.moveCol(-1);
            return true;
        case Qt.Key_Right:
            if (ctrl)
                return false;
            root.moveCol(1);
            return true;
        case Qt.Key_Tab:
            root.select(root.selected + 1, true);
            return true;
        case Qt.Key_Backtab:
            root.select(root.selected - 1, true);
            return true;
        case Qt.Key_Up:
            root.moveRow(-1);
            return true;
        case Qt.Key_Down:
            root.moveRow(1);
            return true;
        case Qt.Key_PageUp:
            root.movePage(-1);
            return true;
        case Qt.Key_PageDown:
            root.movePage(1);
            return true;
        }
        // Ctrl+O; nativeScanCode 32 = the O key on the ru layout too.
        if (ctrl && (event.key === Qt.Key_O || event.nativeScanCode === 32) && root.current?.page) {
            Quickshell.execDetached(["xdg-open", root.current.page]);
            root.requestClose(true);
            return true;
        }
        return false;
    }
    function handleExecute(query: string, isAlt: bool): bool {
        // A query typed faster than the debounce: search it first.
        if (debounce.running) {
            root.search();
            return true;
        }
        root.copy(root.current, isAlt);
        return true;
    }

    // ── Body ──────────────────────────────────────────────────────────
    Component {
        id: bodyComp
        Item {
            id: body
            clip: true

            // Spring follows root.scrollY (keys / wheel set the target).
            property real shownY: root.scrollY
            Behavior on shownY {
                Spring {
                    stiffness: 5
                    damp: 0.5
                    eps: 0.5
                }
            }

            Item {
                id: content
                width: parent.width
                height: root.contentH
                y: -body.shownY

                Item {
                    id: tilesLayer
                    anchors.fill: parent

                Repeater {
                    model: results
                    delegate: Item {
                        id: tile
                        required property int index
                        required property string title
                        required property string preview
                        required property bool ready
                        required property real tx
                        required property real ty
                        required property real th
                        readonly property bool isSel: tile.index === root.selected
                        readonly property bool near: tile.ty + tile.th > body.shownY - root.viewH && tile.ty < body.shownY + root.viewH * 2
                        readonly property bool inView: tile.ty + tile.th > body.shownY && tile.ty < body.shownY + root.viewH
                        x: tile.tx
                        y: tile.ty
                        width: root.colW
                        height: tile.th
                        z: tile.isSel ? 1 : 0
                        scale: tile.isSel ? (root.g.selectScale ?? 1.07) : 1
                        Behavior on scale { Spring { stiffness: 6; damp: 0.45; eps: 0.002 } }

                        RoundedClip {
                            anchors.fill: parent
                            radius: root.g.radius ?? 14
                            visible: tile.near

                            Rectangle {
                                anchors.fill: parent
                                color: root.theme.cardTrack
                                SequentialAnimation on opacity {
                                    running: tile.near && img.status !== AnimatedImage.Ready
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.45; duration: 650; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 1; duration: 650; easing.type: Easing.InOutSine }
                                }
                            }
                            AnimatedImage {
                                id: img
                                anchors.fill: parent
                                source: tile.ready && tile.near ? "file://" + tile.preview : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                                playing: tile.inView && ((root.g.playAll ?? true) || tile.isSel)
                                opacity: status === AnimatedImage.Ready ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 200 } }
                            }
                            // Title on the selected tile.
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: Math.min(parent.height, caption.implicitHeight + 22)
                                opacity: tile.isSel && tile.title !== "" ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 160 } }
                                gradient: Gradient {
                                    GradientStop { position: 0; color: "transparent" }
                                    GradientStop { position: 1; color: root.theme.wallCaptionShade }
                                }
                                Text {
                                    id: caption
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 8
                                    text: tile.title.replace(/\s+GIF\b.*$/i, "")
                                    color: "white"
                                    font.family: root.theme.fontFamily
                                    font.pixelSize: root.theme.fontSizeBody
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                            }
                            // Every tile but the selected one a bit darker
                            // (dimOthers = their brightness).
                            Rectangle {
                                anchors.fill: parent
                                color: root.theme.islandBg
                                opacity: tile.isSel || results.count < 2 ? 0 : 1 - (root.g.dimOthers ?? 0.55)
                                Behavior on opacity { NumberAnimation { duration: 180 } }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.select(tile.index, false)
                            onClicked: mouse => root.copy(results.get(tile.index), (mouse.modifiers & Qt.AltModifier) !== 0)
                        }
                    }
                }
                }

                // Blurred outline around the focus rect: one live copy of the
                // tiles around it, blurred in bandSteps nested rounded rings
                // (outer = weakest, drawn first; inner = strongest).
                Item {
                    id: band
                    readonly property real bw: root.g.bandWidth ?? 60
                    readonly property int steps: Math.max(1, root.g.bandSteps ?? 8)
                    readonly property real r: root.g.radius ?? 14
                    x: root.focusL - band.bw
                    y: root.focusT - band.bw
                    width: root.colW + band.bw * 2
                    height: root.focusH + band.bw * 2
                    visible: !!root.selGeo && results.count > 1 && (root.g.bandBlur ?? 1) > 0

                    ShaderEffectSource {
                        id: bandSrc
                        anchors.fill: parent
                        sourceItem: tilesLayer
                        sourceRect: Qt.rect(band.x, band.y, band.width, band.height)
                        live: true
                        visible: false
                    }
                    Repeater {
                        model: band.steps
                        RoundedClip {
                            id: ring
                            required property int index
                            // k = 0 innermost. (Inside a RoundedClip `parent`
                            // is its inner layer — address it by id.)
                            readonly property int k: band.steps - 1 - index
                            readonly property real grow: band.bw * (k + 1) / band.steps
                            x: band.bw - grow
                            y: band.bw - grow
                            width: root.colW + grow * 2
                            height: root.focusH + grow * 2
                            radius: band.r + grow
                            MultiEffect {
                                x: -ring.x
                                y: -ring.y
                                width: band.width
                                height: band.height
                                source: bandSrc
                                autoPaddingEnabled: false
                                blurEnabled: true
                                blurMax: root.g.blurMax ?? 32
                                blur: (root.g.bandBlur ?? 1) * Math.pow(1 - ring.k / band.steps, root.g.bandCurve ?? 1.4)
                            }
                        }
                    }
                }

                // The selected tile itself, crisp, over the band (its lifted
                // size).
                RoundedClip {
                    id: crisp
                    readonly property real s: root.g.selectScale ?? 1.07
                    readonly property var gs: root.selGeo
                    visible: band.visible
                    width: root.colW * s
                    height: (gs?.h ?? 0) * s
                    x: (gs?.x ?? 0) - (width - root.colW) / 2
                    y: (gs?.y ?? 0) - (height - (gs?.h ?? 0)) / 2
                    radius: (root.g.radius ?? 14) * s
                    ShaderEffectSource {
                        anchors.fill: parent
                        sourceItem: tilesLayer
                        sourceRect: Qt.rect(crisp.x, crisp.y, crisp.width, crisp.height)
                        live: true
                    }
                }
            }

            // Wheel / touchpad scroll the view (pixels).
            WheelHandler {
                target: null
                onWheel: ev => {
                    const d = ev.pixelDelta.y !== 0 ? ev.pixelDelta.y : ev.angleDelta.y / 120 * root.colW * 0.6;
                    root.scrollTo(root.scrollY - d);
                }
            }

            // Content scrolled past an edge fades out there.
            Rectangle {
                width: parent.width
                height: 22
                opacity: Math.min(1, body.shownY / 22)
                gradient: Gradient {
                    GradientStop { position: 0; color: root.theme.islandBg }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 22
                opacity: Math.min(1, Math.max(0, (root.contentH - root.spacing - body.shownY - root.viewH) / 22))
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: root.theme.islandBg }
                }
            }

            // Empty / error / no-key states.
            Column {
                anchors.centerIn: parent
                width: parent.width - 40
                spacing: 10
                visible: results.count === 0
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: !root.apiKey ? "\ueac7" : (root.error !== "" ? "\uea05" : (root.busy ? "\uf257" : "\ueeb5"))
                    font.family: root.theme.iconFamily
                    font.pixelSize: 38
                    color: root.theme.subtleFg
                    SequentialAnimation on opacity {
                        running: root.busy && results.count === 0
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
                    }
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    lineHeight: 1.2
                    color: root.theme.subtleFg
                    font.family: root.theme.fontFamily
                    font.pixelSize: (root.cfg?.subFontSize ?? 14)
                    text: !root.keysLoaded ? ""
                        : !root.apiKey ? I18n.tr("Add a GIPHY or Tenor API key to %1:\n{\"giphy\": \"…\"} or {\"tenor\": \"…\"}\n(developers.giphy.com · developers.google.com/tenor)").arg(root.keysPath.replace(Quickshell.env("HOME"), "~"))
                        : root.error !== "" ? root.error
                        : root.busy ? I18n.tr("Searching…")
                        : I18n.tr("Nothing found")
                }
            }
        }
    }
}
