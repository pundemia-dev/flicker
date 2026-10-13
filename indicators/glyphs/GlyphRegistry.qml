import QtQuick

// Drawn event glyphs by name (event `glyph`). Explicit Components — the
// qml scanner misses files created from dynamic URLs. Aliases map device
// kinds onto one drawing (any over-ear headphones = AirPods Max).
QtObject {
    readonly property var map: ({
            pacman: pacman,
            ghost: ghost,
            coffee: coffee,
            bolt: bolt,
            bluetooth: bluetooth,
            airpods: airpods,
            airpodsMax: airpodsMax,
            headphones: airpodsMax,
            speaker: speaker,
            phone: phone,
            tablet: tablet,
            laptop: laptop,
            watch: watch,
            mouse: mouse,
            keyboard: keyboard,
            gamepad: gamepad,
            lock: lock,
            moon: moon,
            transfer: transfer,
            error: error,
            copy: copy,
            hello: hello,
            shazam: shazam
        })

    property Component pacman: PacmanGlyph {}
    property Component shazam: ShazamGlyph {}
    property Component ghost: GhostGlyph {}
    property Component coffee: CoffeeGlyph {}
    property Component bolt: BoltGlyph {}
    property Component bluetooth: BluetoothGlyph {}
    property Component airpods: AirPodsGlyph {}
    property Component airpodsMax: AirPodsMaxGlyph {}
    property Component speaker: SpeakerGlyph {}
    property Component phone: PhoneGlyph {}
    property Component tablet: TabletGlyph {}
    property Component laptop: LaptopGlyph {}
    property Component watch: WatchGlyph {}
    property Component mouse: MouseGlyph {}
    property Component keyboard: KeyboardGlyph {}
    property Component gamepad: GamepadGlyph {}
    property Component lock: LockGlyph {}
    property Component moon: MoonGlyph {}
    property Component transfer: TransferGlyph {}
    property Component error: ErrorGlyph {}
    property Component copy: CopyGlyph {}
    property Component hello: HelloGlyph {}
}
