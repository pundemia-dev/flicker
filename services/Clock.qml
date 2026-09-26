import QtQuick
import Quickshell

Item {
    readonly property date date: clock.date
    readonly property string time: Qt.formatDateTime(clock.date, "hh:mm")
    readonly property string seconds: Qt.formatDateTime(clock.date, "ss")

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }
}
