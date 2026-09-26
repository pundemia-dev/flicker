import QtQuick

Rectangle {
    property bool blurEnabled: true
    property real blurStrength: 0
    // True-black island: no white wash. An 8% white overlay turned the
    // opaque #000000 body into #141414, so the wash stays transparent and
    // the real backdrop blur (compositor region over translucent areas)
    // remains the only blur. Props kept for the ContentSwap API; a future
    // real in-window blur (MultiEffect/FastBlur) can reuse them.
    color: "transparent"
}
