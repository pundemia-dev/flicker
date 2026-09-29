import QtQuick

Text {
    color: "#E9ECF1"
    // Global shell font: a directory import of ../components shadows
    // QtQuick Text, so every bare `Text {}` in files importing ../components
    // resolves here (verified via runtime probe). Mirrors Theme.fontFamily —
    // this primitive is theme-less, same as its hardcoded color above.
    font.family: "SF Pro Display"
    font.pixelSize: 12
    verticalAlignment: Text.AlignVCenter
    renderType: Text.NativeRendering
}
