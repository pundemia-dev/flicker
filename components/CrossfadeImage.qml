import QtQuick

// Two RoundedImage layers that hand over on a source change: the new art
// decodes in the hidden back layer, then ONE spring driver (p 0 -> 1)
// fades it in over the front one (scaling enterScale -> 1, with the
// spring's overshoot as a small bounce) while the old frame fades out
// (scaling 1 -> exitScale; see exitFade). When the spring lands the roles swap and p
// resets to 0 in the same frame. A source change mid-flight is picked up
// once the current handover lands, so rapid skips never cut a fade short.
// Scale > 1 is unsafe for art filling a clipped surface (corners would
// poke past it) — keep enterScale/exitScale <= 1 there.
Item {
    id: root

    property url source: ""
    property real radius: 0
    property real blur: 0
    property color fallbackColor: "transparent"
    property string fallbackGlyph: ""
    property int glyphSize: 32
    property real enterScale: 1
    property real exitScale: 1
    // false: the outgoing frame stays opaque under the incoming one (a
    // plain crossfade of two translucent layers dips through the
    // background mid-way). Forced on when the incoming layer has no image
    // (empty source / error), otherwise the old art would never leave.
    property bool exitFade: true
    property real stiffness: 3
    property real damp: 0.3

    property int front: 0
    property bool waiting: false
    property real p: 0
    readonly property bool fadesOut: root.exitFade || !root.layerAt(1 - root.front).ready
    readonly property bool flying: drive.running || root.p > 0

    function layerAt(i: int): var {
        return i === 0 ? l0 : l1;
    }
    function kick(): void {
        if (root.flying || root.waiting || root.layerAt(root.front).source === root.source)
            return;
        root.layerAt(1 - root.front).source = root.source;
        root.waiting = true;
        root.tryStart();
    }
    function tryStart(): void {
        if (root.waiting && root.layerAt(1 - root.front).status !== Image.Loading) {
            root.waiting = false;
            drive.restart();
        }
    }

    onSourceChanged: kick()
    Component.onCompleted: l0.source = root.source

    Spring {
        id: drive
        target: root
        property: "p"
        to: 1
        stiffness: root.stiffness
        damp: root.damp
        eps: 0.002
        onFinished: {
            root.front = 1 - root.front;
            root.p = 0;
            root.kick();
        }
    }

    component Layer: RoundedImage {
        required property int idx
        readonly property bool isFront: idx === root.front
        anchors.fill: parent
        radius: root.radius
        blur: root.blur
        fallbackColor: root.fallbackColor
        fallbackGlyph: root.fallbackGlyph
        glyphSize: root.glyphSize
        visible: opacity > 0.001
        // Incoming layer on top so it covers the outgoing one.
        z: isFront ? 0 : 1
        opacity: isFront ? (root.fadesOut ? Math.max(0, 1 - root.p * root.p) : 1) : Math.min(1, root.p)
        scale: isFront ? 1 + (root.exitScale - 1) * Math.min(1, root.p)
                       : root.enterScale + (1 - root.enterScale) * root.p
        onStatusChanged: if (!isFront) root.tryStart()
    }

    Layer { id: l0; idx: 0 }
    Layer { id: l1; idx: 1 }
}
