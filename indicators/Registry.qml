import QtQuick

// Indicator registry: adding an indicator = QML file + entry here (spec).
// `priority` decides eviction order when the island runs out of space
// (higher wins, see IndicatorLayout). `side` places the indicator in the
// left/right row; "plate" indicators are rendered by ClockPlate instead
// (recording/hotspot replace the clock face per spec).
QtObject {
    readonly property var entries: [
        { name: "microphone", side: "left", priority: 3, source: microphoneIndicator },
        { name: "music", side: "left", priority: 2, source: musicIndicator },
        { name: "dictation", side: "left", priority: 2, source: dictationIndicator },
        { name: "timer", side: "right", priority: 1, source: timerIndicator },
        { name: "recording", side: "plate", priority: 3, source: recordingIndicator },
        { name: "hotspot", side: "plate", priority: 3, source: hotspotIndicator }
    ]

    property Component microphoneIndicator: Microphone {}
    property Component musicIndicator: Music {}
    property Component dictationIndicator: DictationWave {}
    property Component timerIndicator: Timer {}
    property Component recordingIndicator: Recording {}
    property Component hotspotIndicator: Hotspot {}
}
