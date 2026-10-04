import QtQuick
import QtQuick.Effects

// In-window blur (spec: MultiEffect, no custom shaders) over this item's own
// children. `amount` 0..1 drives the blur; at 0 the layer is switched OFF so
// idle content renders directly — crisp, no offscreen texture, and input
// goes straight to the children (a layer effect never blocks input anyway).
// This blurs the island's CONTENT (the blur stage of blur->fade), not the
// backdrop: the backdrop behind translucent island areas is the compositor
// blur region in Island.qml. Edge fading lives in components/EdgeFade.qml:
// MultiEffect's mask is a hard alpha threshold here (Qt 6.11, verified Oct
// 2026 — maskSpreadAtMin only shifts the cut, a gradient mask stays binary).
Item {
    id: root
    property bool blurEnabled: true
    property real amount: 0
    // Blur radius at amount 1, in px (MultiEffect blurMax).
    property int blurMax: 32
    readonly property bool active: root.blurEnabled && root.amount > 0.001

    layer.enabled: root.active
    layer.smooth: true
    layer.effect: MultiEffect {
        blurEnabled: true
        blur: Math.max(0, Math.min(1, root.amount))
        blurMax: root.blurMax
        // No padding: the island clips to its own shape anyway, and padding
        // would shift the layer and visibly jump content on/off.
        autoPaddingEnabled: false
    }
}
