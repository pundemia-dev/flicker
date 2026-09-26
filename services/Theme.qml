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
    readonly property color accentRed: "#E04F5F"
    readonly property color accentGreen: "#49C57D"
    readonly property color accentYellow: "#D8BE52"
    readonly property color accentOrange: "#E58B4D"
    readonly property color waveColor: "#A8C1FF"
    readonly property color arcTrack: "#6E7681"
    readonly property color batteryGood: "#59D67A"
    readonly property color batteryWarn: "#E7C45A"
    readonly property color batteryLow: "#E35D5D"
    readonly property int fontSizeClock: 14
    readonly property int fontSizeBody: 12
    readonly property int fontSizeIndicator: 11
    readonly property int fontSizeTiny: 10
}
