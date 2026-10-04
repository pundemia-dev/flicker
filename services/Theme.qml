import QtQuick

QtObject {
    readonly property color islandBg: "#000000"
    readonly property color islandFg: "#E9ECF1"
    // 1px rim over the island edge (DMS approach): masks the zone where the
    // hard compositor blur mask diverges from the smooth painted corner.
    readonly property color islandRim: "#26FFFFFF"
    readonly property int islandRimWidth: 1
    readonly property color minimalBg: "#8D939A"
    readonly property real minimalOpacity: 0.35
    readonly property color subtleFg: "#B9C0CB"
    readonly property color accentRed: "#E4483E"
    readonly property color accentGreen: "#3DBD4E"
    readonly property color accentYellow: "#D8BE52"
    readonly property color accentOrange: "#E58B4D"
    readonly property color waveColor: "#A8C1FF"
    // Dictation wave while the backend is (re)starting and no model is
    // loaded yet: neutral grey instead of the live blue.
    readonly property color waveDim: "#6E7683"
    readonly property color arcTrack: "#6E7681"
    readonly property color arcGlow: "#2E000000"
    readonly property color islandHalo: "#01FFFFFF"
    // Dashboard cards (dark widgets on the true-black island body).
    readonly property color cardBg: "#1C1C1E"
    readonly property color cardTrack: "#2C2C2E"
    readonly property color cardDim: "#99EBEBF5"
    readonly property color cardBlue: "#0F7CEC"
    readonly property color batteryGood: "#59D67A"
    readonly property color batteryWarn: "#E7C45A"
    readonly property color batteryLow: "#E35D5D"
    readonly property int fontSizeClock: 14
    readonly property int fontSizeBody: 12
    readonly property int fontSizeIndicator: 11
    readonly property int fontSizeTiny: 10
    // Global shell font (otf-san-francisco, fc family name "SF Pro Display").
    // Applied by default in components/Text.qml; theme-less spots (launcher
    // TextInput) reference the same family literally.
    readonly property string fontFamily: "SF Pro Display"
    // Icon glyph font (fc family "tabler-icons"; the filled media-control set
    // lives in the U+F6xx plane: prev f697 pause f690 play f691 next f696).
    readonly property string iconFamily: "tabler-icons"
    // Capture overlay: screen dim, crosshair and selection frame.
    readonly property color captureDim: "#000000"
    readonly property color captureCross: "#E9ECF1"
    readonly property color captureSelection: "#E9ECF1"
}
