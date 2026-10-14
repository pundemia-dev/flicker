import QtQuick
import Quickshell
import Quickshell.Io
import "../../components"

// Lock-screen background (user design, Oct 2026): the lock starts on the grab
// taken just before locking (no seam), then every region that differs from
// the wallpaper (scripts/lock/regions.sh → diff.py: windows, the island,
// notifications…) blurs and fades, largest first, one after another (the next
// starts overlapIn of a step before the previous one ends, + gapMs), so the wallpaper shows
// through the blur. Unlock = the exact reverse (smallest returns first), then
// `unlockDone` — the live desktop that follows may differ
// slightly from the grab (accepted).
// Layers: black → wallpaper → base grab (island painted out; the tiles'
// texture source) →
// tiles → black cover (only when locked without a grab: it fades out instead).
Item {
    id: root

    required property var scope
    required property ShellScreen screen
    readonly property var cfg: root.scope?.cfg ?? ({})
    readonly property real dpr: root.screen?.devicePixelRatio ?? 1
    readonly property string grab: root.scope?.grabPath(root.screen?.name ?? "") ?? ""

    // regions.sh answer ({w, h, regions, wallpaper}); null until it lands.
    property var info: null
    property bool dissolved: false
    property bool unlocking: false
    // A moving wallpaper (GIF / video, user decision): no copy of it — the
    // whole grab just blurs (one screen-wide tile that never fades).
    readonly property bool moving: (root.info?.kind ?? "image") !== "image"
    readonly property bool hasWallPath: (root.info?.wallpaper ?? "") !== "" && !root.moving
    readonly property bool hasWall: root.hasWallPath && wallMedia.ready
    // Dissolve once the wallpaper is on (or failed / took > wallWaitMs).
    property bool wallTimedOut: false
    readonly property bool ready: root.info !== null
        && (!root.hasWallPath || root.hasWall || wallMedia.failed || root.wallTimedOut)
    Timer {
        running: root.info !== null && root.hasWallPath && !root.hasWall
        interval: root.cfg.wallWaitMs ?? 1500
        onTriggered: root.wallTimedOut = true
    }

    signal unlockDone

    // The base grab (texture source for LockField's bar crop); null = no grab.
    readonly property Item grabItem: root.grab !== "" ? grabImg : null

    // Sequence step per region: dissolveMs / returnMs, shortened so the whole
    // chain fits sequenceMaxMs when there are many regions.
    // The next region starts `overlap` (0..1 of a step) before the previous
    // one ends: start spacing = step × (1 − overlap) + gapMs.
    readonly property real overlapIn: Math.max(0, Math.min(0.95, root.cfg.overlapIn ?? 0.6))
    readonly property real overlapOut: Math.max(0, Math.min(0.95, root.cfg.overlapOut ?? 0.6))
    readonly property int stepIn: root.stepFor(root.cfg.dissolveMs ?? 400, root.overlapIn)
    readonly property int stepOut: root.stepFor(root.cfg.returnMs ?? 300, root.overlapOut)
    function stepFor(ms: int, overlap: real): int {
        const n = Math.max(1, root.tiles.length);
        const gap = root.cfg.gapMs ?? 0;
        // total = step + (n − 1) × (step × (1 − overlap) + gap) ≤ sequenceMaxMs
        const cap = ((root.cfg.sequenceMaxMs ?? 2000) - (n - 1) * gap) / (1 + (n - 1) * (1 - overlap));
        return Math.max(60, Math.min(ms, Math.floor(cap)));
    }

    // Region rects in logical px, grown by tileMarginPx, clipped to the screen.
    readonly property var tiles: {
        const i = root.info;
        if (!i || !(i.w > 0) || root.width <= 0)
            return [];
        const m = root.cfg.tileMarginPx ?? 24;
        if (root.moving)
            return [{ x: 0, y: 0, w: Math.ceil(root.width), h: Math.ceil(root.height) }];
        const sx = root.width / i.w, sy = root.height / i.h;
        return (i.regions ?? []).map(r => {
            const x0 = Math.max(0, Math.floor(r.x * sx - m));
            const y0 = Math.max(0, Math.floor(r.y * sy - m));
            const x1 = Math.min(root.width, Math.ceil((r.x + r.w) * sx + m));
            const y1 = Math.min(root.height, Math.ceil((r.y + r.h) * sy + m));
            return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
        });
    }

    function playUnlock(): void {
        root.unlocking = true;
        root.dissolved = false;
        startTimer.stop();
        settleCheck.restart();
    }

    function backAtRest(): bool {
        for (let k = 0; k < tileRepeater.count; k++) {
            const t = tileRepeater.itemAt(k);
            if (t && (t.gone || !t.atRest))
                return false;
        }
        return base.p > 0.99 && (root.grab !== "" || cover.p > 0.99);
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    // The still wallpaper as wallr shows it ("fill" = cover crop).
    Image {
        id: wallMedia
        readonly property bool ready: status === Image.Ready
        readonly property bool failed: status === Image.Error
        anchors.fill: parent
        source: root.hasWallPath ? "file://" + root.info.wallpaper : ""
        sourceSize: Qt.size(Math.round(root.width * root.dpr), Math.round(root.height * root.dpr))
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
    }

    // The grab, loaded synchronously so the lock's FIRST frame already shows
    // it. Outside the regions it equals the wallpaper, so fading it out once
    // the tiles cover the regions is invisible (hides scaling/dither drift).
    Item {
        id: base
        anchors.fill: parent
        property real p: root.dissolved ? 0 : 1
        Behavior on p {
            NumberAnimation {
                duration: root.dissolved ? (root.cfg.dissolveMs ?? 400) : (root.cfg.returnMs ?? 300)
                easing.type: Easing[root.cfg.easing ?? "InOutSine"] ?? Easing.InOutSine
            }
        }
        opacity: root.hasWall ? Math.max(0, Math.min(1, base.p)) : 1

        // The island painted out (diff.py --hole, once it answered): the
        // tiles crop THIS, so the grab's own island never stays behind when
        // LockField (which shows the raw bar + arcs at first) flies off.
        Image {
            anchors.fill: parent
            source: (root.info?.inpainted ?? "") !== "" ? "file://" + root.info.inpainted
                : root.grab !== "" ? "file://" + root.grab : ""
            fillMode: Image.Stretch
            asynchronous: false
            cache: false
        }
    }

    // The raw grab: texture for LockField's bar crop (never painted out).
    Image {
        id: grabImg
        anchors.fill: parent
        opacity: 0
        source: root.grab !== "" ? "file://" + root.grab : ""
        fillMode: Image.Stretch
        asynchronous: false
        cache: false
    }

    Repeater {
        id: tileRepeater
        model: root.grab !== "" ? root.tiles : []

        LockTile {
            id: tile
            required property var modelData
            required property int index

            x: tile.modelData.x
            y: tile.modelData.y
            width: tile.modelData.w
            height: tile.modelData.h
            source: base
            cfg: root.cfg
            fades: root.hasWall
            inMs: root.stepIn
            outMs: root.stepOut

            // Largest first on the way out, smallest first on the way back; strictly
            // one after another.
            property bool want: root.dissolved
            onWantChanged: {
                const n = tileRepeater.count;
                const rank = tile.want ? tile.index : n - 1 - tile.index;
                const step = tile.want ? root.stepIn * (1 - root.overlapIn) : root.stepOut * (1 - root.overlapOut);
                const spacing = step + (root.cfg.gapMs ?? 0);
                kick.interval = Math.max(1, Math.round(rank * spacing));
                kick.restart();
            }
            Timer {
                id: kick
                onTriggered: tile.gone = tile.want
            }
        }
    }

    // Island rect (skin coords): painted out of the base grab (+ the
    // holeMarginPx halo / side arcs), its copy is LockField.
    property var hole: null
    readonly property var holePx: {
        const h = root.hole, m = root.cfg.holeMarginPx ?? 14;
        if (!h)
            return "";
        const x = Math.max(0, h.x - m), y = Math.max(0, h.y - m);
        return [x, y, h.x + h.width + m - x, h.y + h.height + m - y].map(v => Math.round(v * root.dpr)).join(",");
    }

    Rectangle {
        id: cover
        anchors.fill: parent
        color: "black"
        visible: root.grab === ""
        property real p: root.dissolved ? 0 : 1
        Behavior on p {
            NumberAnimation {
                duration: root.dissolved ? (root.cfg.dissolveMs ?? 400) : (root.cfg.returnMs ?? 300)
                easing.type: Easing[root.cfg.easing ?? "InOutSine"] ?? Easing.InOutSine
            }
        }
        opacity: Math.max(0, Math.min(1, cover.p))
    }

    // Dissolve once the regions AND the wallpaper are in (+ startDelayMs).
    onReadyChanged: if (root.ready && !root.unlocking)
        startTimer.restart()
    Timer {
        id: startTimer
        interval: root.cfg.startDelayMs ?? 120
        onTriggered: root.dissolved = true
    }

    Timer {
        id: settleCheck
        interval: 50
        repeat: true
        onTriggered: if (root.backAtRest()) {
            settleCheck.stop();
            root.unlockDone();
        }
    }

    // Without an answer in time: the whole grab just blurs (no wallpaper).
    Timer {
        running: root.info === null
        interval: root.cfg.diffTimeoutMs ?? 1500
        onTriggered: if (root.info === null)
            root.info = { w: 1, h: 1, regions: [{ x: 0, y: 0, w: 1, h: 1 }], wallpaper: "" }
    }

    Process {
        running: root.screen !== null
        command: ["bash", Quickshell.shellDir + "/scripts/lock/regions.sh", root.grab !== "" ? root.grab : "-", root.screen?.name ?? "",
            "--grid", String(root.cfg.diffGrid ?? 240), "--threshold", String(root.cfg.diffThreshold ?? 20),
            "--max-coverage", String(root.cfg.diffMaxCoverage ?? 0.85),
            "--hole", root.holePx, "--inpaint-out", root.grab !== "" ? root.grab.replace(/\.ppm$/, "-inpaint.ppm") : "",
            "--strip", String(root.cfg.inpaintStripPx ?? 3), "--inpaint-blur", String(root.cfg.inpaintBlur ?? 8)]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.info !== null)
                    return;
                try {
                    root.info = JSON.parse(text.trim());
                } catch (e) {
                    console.warn("[lock] regions:", e, text);
                }
            }
        }
    }
}
