import QtQuick
import QtQuick.Effects
import "../components"

// The single blur->fade content transition (spec). The content itself is
// blurred in-window (BlurSurface = MultiEffect). A swap overlaps old and new:
//   1. blur rises on the old content (blurInMs)
//   2. handover: the old content's last frame is frozen into a blurred ghost
//      (ShaderEffectSource, live: false), the owner swaps to the new content
//   3. crossfade under blur: ghost fades out (fadeOutMs) WHILE the new
//      content fades in still blurred (fadeInMs)
//   4. delay, then the blur falls on the new content (blurOutMs)
// The owner only ever renders ONE content tree (it switches at the handover,
// see shownKey/committed); the ghost is what lets both be seen at once.
Item {
    id: root
    property bool showing: true
    property bool blurEnabled: true
    // Blur radius at full strength, px (config effects.contentBlurMax).
    property int blurMax: 32
    // Edge fade width at full blur, px (config effects.contentEdgeFade):
    // the content fades out towards its edges only while it is blurred.
    property real edgeFade: 0
    // Background the content sits on (edge fade blends into it).
    property color fadeColor: "black"
    property int blurInMs: 110
    property int fadeInMs: 160
    property int blurOutMs: 110
    property int fadeOutMs: 160
    property int stageDelayMs: 70
    // Change swapKey to replay the blur->fade pattern for an in-place content
    // swap (bar <-> module <-> ticker) without tearing down the container.
    property var swapKey
    // Key of the content actually rendered. Lags swapKey: it flips at the
    // handover, right after the old frame is frozen into the ghost.
    property var shownKey
    readonly property bool settled: shownKey === swapKey
    // Emitted when shownKey flips: the owner swaps its content here.
    signal committed
    // Island corner radius: transitions are clipped to this rounded shape.
    property real surfaceRadius: 0
    default property alias content: liveItem.data
    readonly property real contentOpacity: contentRoot.opacity
    readonly property real blurAmount: contentRoot.amount

    function commit(): void {
        root.shownKey = root.swapKey;
        root.committed();
    }

    // Start mirroring the live content into the ghost texture (only while a
    // swap runs: an idle live ShaderEffectSource would re-render every frame).
    function armGhost(): void {
        ghost.sourceItem = liveItem;
        ghost.live = true;
    }

    // Freeze the old frame, put it on screen at the content's current
    // opacity, hide the live tree, then swap it to the new content. The ghost
    // keeps the size it was captured at (top-centred, like island content)
    // so the island's resize never stretches it.
    function handover(): void {
        ghostRoot.width = root.width;
        ghostRoot.height = root.height;
        ghost.live = false;
        ghostRoot.opacity = contentRoot.opacity;
        contentRoot.opacity = 0;
        root.commit();
    }

    function releaseGhost(): void {
        ghostRoot.opacity = 0;
        ghost.sourceItem = null;
    }

    Component.onCompleted: {
        // Created hidden (showing: false): start invisible so the first
        // showing flip plays the regular blur->fade entrance.
        if (!root.showing)
            contentRoot.opacity = 0;
        commit();
    }
    onShowingChanged: showing ? inAnim.restart() : outAnim.restart()
    onSwapKeyChanged: {
        if (showing)
            swapAnim.restart();
        else
            commit();
    }

    // While a transition runs, everything below is clipped to the island's
    // ROUNDED shape: the island's own clip is rectangular, so the edge-fade
    // strips (and blur spill) showed in the corners outside the rounding.
    // MultiEffect's binary mask (hard-edged; fine under the island's own
    // rim). Idle: no layer, the content renders directly.
    readonly property bool shaping: contentRoot.amount > 0.001 || ghostRoot.opacity > 0.001

    Item {
        id: shaped
        anchors.fill: parent
        layer.enabled: root.shaping
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: shapeMask
            autoPaddingEnabled: false
        }

        // Frozen, blurred last frame of the outgoing content.
        BlurSurface {
            id: ghostRoot
            x: (root.width - width) / 2
            y: 0
            blurEnabled: root.blurEnabled
            blurMax: root.blurMax
            amount: 1
            opacity: 0
            visible: opacity > 0.001

            ShaderEffectSource {
                id: ghost
                anchors.fill: parent
                sourceItem: null
                live: false
                hideSource: false
            }
        }

        BlurSurface {
            id: contentRoot
            anchors.fill: parent
            blurEnabled: root.blurEnabled
            blurMax: root.blurMax
            amount: 0
            opacity: 1

            Item {
                id: liveItem
                anchors.fill: parent
            }
        }

        // Edge fade over both layers, only while blur exists: as strong as the
        // blur currently on screen (live blur, or the always-blurred ghost).
        EdgeFade {
            anchors.fill: parent
            color: root.fadeColor
            edgeWidth: root.edgeFade
            strength: root.blurEnabled ? Math.max(contentRoot.amount, ghostRoot.opacity) : 0
        }
    }

    Item {
        id: shapeMask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            anchors.fill: parent
            radius: root.surfaceRadius
            color: "white"
        }
    }

    // Enter from nothing: content arrives blurred, fades in, then sharpens.
    SequentialAnimation {
        id: inAnim
        PropertyAction { target: contentRoot; property: "amount"; value: 1 }
        NumberAnimation { target: contentRoot; property: "opacity"; to: 1; duration: root.fadeInMs }
        PauseAnimation { duration: root.stageDelayMs }
        NumberAnimation { target: contentRoot; property: "amount"; to: 0; duration: root.blurOutMs }
    }

    // Leave to nothing: content blurs, then fades out.
    SequentialAnimation {
        id: outAnim
        NumberAnimation { target: contentRoot; property: "amount"; to: 1; duration: root.blurInMs }
        PauseAnimation { duration: root.stageDelayMs }
        NumberAnimation { target: contentRoot; property: "opacity"; to: 0; duration: root.fadeOutMs }
    }

    // Overlapping swap (see header). commit reads the LATEST swapKey, so a
    // restart mid-swap re-captures whatever is live and lands on the newest.
    SequentialAnimation {
        id: swapAnim
        ScriptAction { script: root.armGhost() }
        NumberAnimation { target: contentRoot; property: "amount"; to: 1; duration: root.blurInMs }
        ScriptAction { script: root.handover() }
        ParallelAnimation {
            NumberAnimation { target: ghostRoot; property: "opacity"; to: 0; duration: root.fadeOutMs }
            NumberAnimation { target: contentRoot; property: "opacity"; to: 1; duration: root.fadeInMs }
        }
        PauseAnimation { duration: root.stageDelayMs }
        NumberAnimation { target: contentRoot; property: "amount"; to: 0; duration: root.blurOutMs }
        ScriptAction { script: root.releaseGhost() }
    }
}
