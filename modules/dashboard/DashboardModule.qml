import QtQuick
import QtQuick.Layouts
import "../../components"
import "./cards"

// Dashboard: grid-first layout. The grid is 6 columns x 4 rows of cards
// (Config.dashboard.unit = one square side, px); a fixed 1-unit header
// block sits above it. Each card hardcodes its footprint (spanCols/spanRows
// in its own file), positions are explicit below, and card sizes are
// locked via min=max=preferred = spanPx(span) — bare preferred loses to
// fillWidth stretch + content minimums and columns split unevenly. Card
// content adapts to the allocated rect (adaptive fonts, row counts, ring
// geometry) — never the reverse. Island size in config must match:
// 2*margins + header + gap + 4*unit + 3*gap (currently 538x450).
//
// 6x4 plan (C = columns span, R = rows span):
//   row 0: weather (4x1) + system (2x2)
//   row 1: battery (4x1) + system
//   row 2: updates (2x1) + media (4x1)
//   row 3: events (2x1) + processes (4x1)
//
// NOTE: no Flickable / fullscreen MouseArea here, deliberately. The
// swipe-up module close is handled by GestureZones BELOW the island
// content: presses must fall through the dashboard (only small controls
// like media buttons may accept them).
Item {
    id: root
    signal closeRequested

    property var clock: null
    property var battery: null
    property var players: null
    property var systemUsage: null
    property var weather: null
    property var theme: null
    property var dash: null

    readonly property real _unit: (dash?.unit) ?? 80
    readonly property int _cols: (dash?.cols) ?? 5
    readonly property real _margins: (dash?.margins) ?? 14
    readonly property real _spacing: (dash?.spacing) ?? 12

    // Pixel size of an n-unit span (cells + inner gaps).
    function spanPx(n: int): real {
        return n * root._unit + (n - 1) * root._spacing;
    }

    Column {
        id: content
        anchors.fill: parent
        anchors.margins: root._margins
        spacing: root._spacing

        ClockHeader {
            width: parent.width
            height: root._unit
            clock: root.clock
            theme: root.theme
            dash: root.dash
        }

        GridLayout {
            width: parent.width
            height: parent.height - root._unit - root._spacing
            columns: root._cols
            rowSpacing: root._spacing
            columnSpacing: root._spacing

            WeatherCard {
                id: weatherCard
                Layout.row: 0
                Layout.column: 0
                Layout.columnSpan: weatherCard.spanCols
                Layout.fillWidth: true
                Layout.preferredWidth: root.spanPx(weatherCard.spanCols)
                Layout.preferredHeight: root.spanPx(weatherCard.spanRows)
                weather: root.weather
                clock: root.clock
                theme: root.theme
                dash: root.dash
            }
            SystemLoadCard {
                id: systemCard
                Layout.row: 0
                Layout.column: 4
                Layout.columnSpan: systemCard.spanCols
                Layout.rowSpan: systemCard.spanRows
                Layout.fillWidth: true
                Layout.preferredWidth: root.spanPx(systemCard.spanCols)
                Layout.minimumWidth: root.spanPx(systemCard.spanCols)
                Layout.maximumWidth: root.spanPx(systemCard.spanCols)
                Layout.preferredHeight: root.spanPx(systemCard.spanRows)
                systemUsage: root.systemUsage
                theme: root.theme
                dash: root.dash
            }
            BatteryCard {
                id: batteryCard
                Layout.row: 1
                Layout.column: 0
                Layout.columnSpan: batteryCard.spanCols
                Layout.fillWidth: true
                Layout.preferredWidth: root.spanPx(batteryCard.spanCols)
                Layout.minimumWidth: root.spanPx(batteryCard.spanCols)
                Layout.maximumWidth: root.spanPx(batteryCard.spanCols)
                Layout.preferredHeight: root.spanPx(batteryCard.spanRows)
                battery: root.battery
                theme: root.theme
                dash: root.dash
            }

            UpdatesCard {
                id: updatesCard
                Layout.row: 2
                Layout.column: 0
                Layout.columnSpan: updatesCard.spanCols
                Layout.fillWidth: true
                Layout.preferredWidth: root.spanPx(updatesCard.spanCols)
                Layout.minimumWidth: root.spanPx(updatesCard.spanCols)
                Layout.maximumWidth: root.spanPx(updatesCard.spanCols)
                Layout.preferredHeight: root.spanPx(updatesCard.spanRows)
                theme: root.theme
                dash: root.dash
            }
            MediaCard {
                id: mediaCard
                Layout.row: 2
                Layout.column: 2
                Layout.columnSpan: mediaCard.spanCols
                Layout.fillWidth: true
                Layout.preferredWidth: root.spanPx(mediaCard.spanCols)
                Layout.minimumWidth: root.spanPx(mediaCard.spanCols)
                Layout.maximumWidth: root.spanPx(mediaCard.spanCols)
                Layout.preferredHeight: root.spanPx(mediaCard.spanRows)
                players: root.players
                theme: root.theme
                dash: root.dash
            }

            EventsCard {
                id: eventsCard
                Layout.row: 3
                Layout.column: 0
                Layout.columnSpan: eventsCard.spanCols
                Layout.fillWidth: true
                Layout.preferredWidth: root.spanPx(eventsCard.spanCols)
                Layout.minimumWidth: root.spanPx(eventsCard.spanCols)
                Layout.maximumWidth: root.spanPx(eventsCard.spanCols)
                Layout.preferredHeight: root.spanPx(eventsCard.spanRows)
                theme: root.theme
                dash: root.dash
            }
            ProcessesCard {
                id: processesCard
                Layout.row: 3
                Layout.column: 2
                Layout.columnSpan: processesCard.spanCols
                Layout.fillWidth: true
                Layout.preferredWidth: root.spanPx(processesCard.spanCols)
                Layout.minimumWidth: root.spanPx(processesCard.spanCols)
                Layout.maximumWidth: root.spanPx(processesCard.spanCols)
                Layout.preferredHeight: root.spanPx(processesCard.spanRows)
                systemUsage: root.systemUsage
                theme: root.theme
                dash: root.dash
            }
        }
    }
}
