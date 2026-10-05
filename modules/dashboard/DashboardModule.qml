import QtQuick
import "../../components"
import "./cards"
import "DashMetrics.js" as DashMetrics

// Dashboard: grid-first layout. A thin header strip (time left, date right,
// Config.dashboard.headerHeight) sits above an 8 x 3 grid of square cells
// (Config.dashboard.unit = cell side, px). Each card hardcodes its footprint
// (spanCols/spanRows in its own file); positions are explicit below via
// cellX/cellY, sizes via spanPx — no GridLayout stretch to fight. Card
// content adapts to the allocated rect, never the reverse. Island size in
// is derived from the same metrics (DashMetrics.islandSize): W = 2*margins +
// 8*unit + 7*gap, H = 2*margins + header + gap + 3*unit + 2*gap, all scaled
// by Config.dashboard.scale (cards get the scaled `dash`, plus `k` for
// their own literal px).
//
// 8x3 plan (mixed shapes; the 2x2 squares are staggered across rows so
// no row reads as a line of identical squares):
//   K K W W W W M M     K = calendar 2x2,    W = weather 4x1
//   K K S S B B M M     M = media 2x2,       S = system 2x2
//   T T S S P P P P     B = battery 2x1,     P = processes 4x1
//                       T = sensors 2x1 (CPU °C + fans)
// Updates/Events cards stay in cards/ but are off the grid (empty states
// only until their backends exist).
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
    property var sensors: null
    property var theme: null
    property var dash: null
    // Scaled metrics handed to every card (raw config stays in `dash`).
    readonly property var m: DashMetrics.scaled(dash)

    readonly property real _unit: (m?.unit) ?? 80
    readonly property real _margins: (m?.margins) ?? 9
    readonly property real _spacing: (m?.spacing) ?? 8
    readonly property real _headerH: (m?.headerHeight) ?? 40

    // Shared-element slots (core/TransitionLayer): header time.
    function sharedSlot(key: string): var {
        return key === "time" ? header.timeSlot : null;
    }

    // Pixel size of an n-unit span (cells + inner gaps).
    function spanPx(n: int): real {
        return n * root._unit + (n - 1) * root._spacing;
    }
    function cellX(col: int): real {
        return col * (root._unit + root._spacing);
    }
    function cellY(row: int): real {
        return row * (root._unit + root._spacing);
    }

    ClockHeader {
        id: header
        x: root._margins
        y: root._margins
        width: root.width - 2 * root._margins
        height: root._headerH
        clock: root.clock
        theme: root.theme
        dash: root.m
    }

    Item {
        id: grid
        x: root._margins
        y: header.y + header.height + root._spacing
        width: root.width - 2 * root._margins
        height: root.height - y - root._margins

        CalendarCard {
            x: root.cellX(0)
            y: root.cellY(0)
            width: root.spanPx(spanCols)
            height: root.spanPx(spanRows)
            clock: root.clock
            theme: root.theme
            dash: root.m
        }
        SensorsCard {
            x: root.cellX(0)
            y: root.cellY(2)
            width: root.spanPx(spanCols)
            height: root.spanPx(spanRows)
            sensors: root.sensors
            theme: root.theme
            dash: root.m
        }
        WeatherCard {
            x: root.cellX(2)
            y: root.cellY(0)
            width: root.spanPx(spanCols)
            height: root.spanPx(spanRows)
            weather: root.weather
            clock: root.clock
            theme: root.theme
            dash: root.m
        }
        SystemLoadCard {
            x: root.cellX(2)
            y: root.cellY(1)
            width: root.spanPx(spanCols)
            height: root.spanPx(spanRows)
            systemUsage: root.systemUsage
            theme: root.theme
            dash: root.m
        }
        MediaCard {
            x: root.cellX(6)
            y: root.cellY(0)
            width: root.spanPx(spanCols)
            height: root.spanPx(spanRows)
            players: root.players
            theme: root.theme
            dash: root.m
        }
        BatteryCard {
            x: root.cellX(4)
            y: root.cellY(1)
            width: root.spanPx(spanCols)
            height: root.spanPx(spanRows)
            battery: root.battery
            theme: root.theme
            dash: root.m
        }
        ProcessesCard {
            x: root.cellX(4)
            y: root.cellY(2)
            width: root.spanPx(spanCols)
            height: root.spanPx(spanRows)
            systemUsage: root.systemUsage
            theme: root.theme
            dash: root.m
        }
    }
}
