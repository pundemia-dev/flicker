import QtQuick
import "../../components"

// One dissolving region of the lock-in grab: a crop of the hidden grab image
// (ShaderEffectSource sourceRect, logical px) that blurs and then fades, so
// the wallpaper below shows through the blur. `p` 1 = the grab as it was,
// 0 = gone; the blur builds over the first `blurLead` of the way, the fade
// starts below `fadeFrom`; timed (one step of LockBackdrop's sequence, `easing`). No padding on the blur: the edges go translucent,
// so the tile is grown by `lock.tileMarginPx` onto plain wallpaper pixels
// (where the grab == the wallpaper) and its border never reads.
BlurSurface {
    id: root

    required property Item source
    required property var cfg
    // Without a wallpaper behind (GIF/video/unknown) the tile only blurs.
    property bool fades: true
    property bool gone: false
    // One step of the sequence (LockBackdrop.stepIn / stepOut).
    property int inMs: 400
    property int outMs: 300

    property real p: root.gone ? 0 : 1
    // Timed, not a spring (user: a smoother slide into / out of the blur).
    Behavior on p {
        NumberAnimation {
            duration: root.gone ? root.inMs : root.outMs
            easing.type: Easing[root.cfg.easing ?? "InOutSine"] ?? Easing.InOutSine
        }
    }
    readonly property bool atRest: Math.abs(root.p - (root.gone ? 0 : 1)) < 0.01

    readonly property real q: Math.max(0, Math.min(1, root.p))
    blurMax: root.cfg.blurMax ?? 64
    amount: Math.min(1, (1 - root.q) / Math.max(0.01, root.cfg.blurLead ?? 0.5))
    opacity: root.fades ? Math.min(1, root.q / Math.max(0.01, root.cfg.fadeFrom ?? 0.7)) : 1

    ShaderEffectSource {
        anchors.fill: parent
        sourceItem: root.source
        sourceRect: Qt.rect(root.x, root.y, root.width, root.height)
    }
}
