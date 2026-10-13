import QtQuick

// Indicator registry: adding an indicator = QML file + entry here (spec).
// `priority` decides eviction order when the island runs out of space
// (higher wins, see IndicatorLayout). `side` places the indicator in the
// left/right row; "plate" indicators are rendered by ClockPlate instead
// (recording/hotspot replace the clock face per spec). Event indicators
// (services/Events.qml, one at a time) are split in two halves: the glyph
// at the far left of the row, the text at the far right.
QtObject {
    readonly property var entries: [
        { name: "eventIcon", side: "left", priority: 4, source: eventIconIndicator },
        { name: "privacy", side: "left", priority: 3, source: privacyIndicator },
        { name: "music", side: "left", priority: 2, source: musicIndicator },
        { name: "dictation", side: "left", priority: 2, source: dictationIndicator },
        { name: "timer", side: "left", priority: 1, source: timerIndicator },
        { name: "eventText", side: "right", priority: 4, source: eventTextIndicator },
        { name: "recording", side: "plate", priority: 3, source: recordingIndicator },
        { name: "hotspot", side: "plate", priority: 3, source: hotspotIndicator }
    ]

    property Component eventIconIndicator: EventIcon {}
    property Component eventTextIndicator: EventText {}
    property Component privacyIndicator: PrivacyDot {}
    property Component musicIndicator: Music {}
    property Component dictationIndicator: DictationWave {}
    property Component timerIndicator: TimerRing {}
    property Component recordingIndicator: Recording {}
    property Component hotspotIndicator: Hotspot {}
}
