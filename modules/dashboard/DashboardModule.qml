import QtQuick
import "../../components"
import "../quicksettings"
import "./cards"
import "DashCatalog.js" as DashCatalog
import "DashMetrics.js" as DashMetrics
import "../quicksettings/QsGrid.js" as QsGrid

// Dashboard: grid-first layout. A thin header strip (time left, date right,
// Config.dashboard.headerHeight) sits above an invisible grid of square
// cells (Config.dashboard.unit = cell side, px; `cols` columns, rows grow
// with the cards). The layout is STATE (services/DashboardLayout, persisted),
// edited like Quick Settings with the same QsGrid engine; allowed footprints
// per card live in DashCatalog.js. Card content adapts to the allocated
// rect, never the reverse. Island size is derived from the same metrics +
// the layout's rows (DashMetrics.islandSize).
//
// Edit mode (long press anywhere on the dashboard, IPC dashboardEdit): drag a
// card to move it (others are pushed aside live, equal cards swap), drag the
// bottom-right arc to resize (nearest allowed footprint), "−" hides, the
// footer adds hidden cards back; "Done", a tap on empty space or closing
// saves. An extra empty row below the grid takes drops.
//
// Presses: this module owns them (background MouseArea under the cards,
// like Quick Settings), so GestureZones never sees them and the swipe-up
// close is done here (same `closeDistance` as GestureZones). A passive
// TapHandler for the long press was tried: GestureZones' exclusive grab
// below cancelled it, or it starved the swipe — flaky either way.
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
    // services/DashboardLayout.
    property var layout: null
    // Upward drag that closes the module (Config.gestures.presentationDragThreshold).
    property real closeDistance: 30

    readonly property real _unit: (dash?.unit) ?? 80
    readonly property real _margins: (dash?.margins) ?? 9
    readonly property real _spacing: (dash?.spacing) ?? 8
    readonly property real _headerH: (dash?.headerHeight) ?? 40
    readonly property real _pitch: root._unit + root._spacing
    readonly property int _cols: (dash?.cols) ?? 8
    readonly property var editCfg: DashMetrics.edit(root.dash ?? {})
    readonly property bool editing: root.layout?.editing ?? false

    // Card being moved/resized (only one at a time).
    property string activeId: ""

    // Shared-element slots (core/TransitionLayer): header time.
    function sharedSlot(key: string): var {
        return key === "time" ? header.timeSlot : null;
    }

    // Pixel size of an n-unit span (cells + inner gaps).
    function spanPx(n: int): real {
        return n * root._unit + (n - 1) * root._spacing;
    }
    function cellPx(n: int): real {
        return n * root._pitch;
    }

    Component.onDestruction: root.layout?.endEdit()

    function componentFor(id: string): Component {
        return ({
            calendar: calendarComp, weather: weatherComp, media: mediaComp, system: systemComp,
            battery: batteryComp, sensors: sensorsComp, processes: processesComp,
            updates: updatesComp, events: eventsComp
        })[id] ?? null;
    }

    // Everything the cards do not take: long press enters edit mode (iOS
    // home screen, cards included — they take no presses), swipe up closes,
    // in edit mode a tap on empty space saves and leaves.
    MouseArea {
        id: bg
        anchors.fill: parent
        pressAndHoldInterval: root.editCfg.holdMs
        property point start
        property bool moved: false
        property bool held: false
        property bool fired: false
        onPressed: mouse => {
            start = Qt.point(mouse.x, mouse.y);
            moved = false;
            held = false;
            fired = false;
        }
        onPressAndHold: {
            if (moved || root.editing)
                return;
            held = true;
            root.layout?.beginEdit();
        }
        onPositionChanged: mouse => {
            const dy = mouse.y - start.y;
            if (Math.hypot(mouse.x - start.x, dy) > 8)
                moved = true;
            if (!root.editing && !held && !fired && dy < -root.closeDistance) {
                fired = true;
                root.closeRequested();
            }
        }
        onReleased: {
            if (root.editing && !held && !moved)
                root.layout?.endEdit();
        }
    }

    ClockHeader {
        id: header
        x: root._margins
        y: root._margins
        width: root.width - 2 * root._margins
        height: root._headerH
        clock: root.clock
        theme: root.theme
        dash: root.dash
    }

    Item {
        id: grid
        x: root._margins
        y: header.y + header.height + root._spacing
        width: DashMetrics.innerWidth(root.dash ?? {})
        height: DashMetrics.gridHeight(root.dash ?? {}, root.layout?.rows ?? 0, root.editing)

        // Empty-slot outlines in edit mode (the grid the cards snap to).
        Repeater {
            model: root.editing ? root._cols * DashMetrics.gridRows(root.layout?.rows ?? 0, true) : 0
            delegate: Rectangle {
                required property int index
                x: root.cellPx(index % root._cols) + (root._unit - width) / 2
                y: root.cellPx(Math.floor(index / root._cols)) + (root._unit - height) / 2
                width: root._unit * 0.86
                height: width
                radius: ((root.dash?.cardRadius) ?? 20) * 0.86
                color: "transparent"
                border.width: 1
                border.color: "#1FFFFFFF"
            }
        }

        Repeater {
            model: DashCatalog.IDS
            delegate: DashTile {
                id: tile
                required property string modelData
                readonly property var rect: root.layout?.rectOf(modelData) ?? null
                // Last placed rect, kept while the card hides (scale-out in place).
                property var last: rect ?? ({ x: 0, y: 0, w: 1, h: 1 })
                onRectChanged: if (rect) last = rect

                // Pointer-follow while moving; animate = springs on. Toggled in
                // this order on release so the return glides (see moveEnded).
                property bool follow: false
                property bool animate: true
                property point grabOrigin
                property point dragOffset

                cardId: modelData
                editCfg: root.editCfg
                radius: (root.dash?.cardRadius) ?? 20
                theme: root.theme
                editing: root.editing
                content: root.componentFor(modelData)
                z: follow ? 2 : (root.activeId === modelData ? 1 : 0)

                x: follow ? grabOrigin.x + dragOffset.x : root.cellPx(last.x)
                y: follow ? grabOrigin.y + dragOffset.y : root.cellPx(last.y)
                width: root.spanPx(last.w)
                height: root.spanPx(last.h)
                Behavior on x { enabled: tile.animate; Spring {} }
                Behavior on y { enabled: tile.animate; Spring {} }
                Behavior on width { enabled: tile.animate; Spring {} }
                Behavior on height { enabled: tile.animate; Spring {} }

                scale: rect ? (follow ? 1.04 : 1) : 0.4
                opacity: rect ? 1 : 0
                visible: opacity > 0.01
                Behavior on scale { Spring { eps: 0.005 } }
                Behavior on opacity { Spring { eps: 0.01 } }

                onRemoveRequested: root.layout.remove(modelData)

                onMoveStarted: {
                    root.activeId = modelData;
                    grabOrigin = Qt.point(x, y);
                    dragOffset = Qt.point(0, 0);
                    animate = false;
                    follow = true;
                }
                onMoveUpdated: (dx, dy) => {
                    dragOffset = Qt.point(dx, dy);
                    const r = root.layout.itemOf(modelData);
                    if (!r)
                        return;
                    // Target cell under the card's top-left; one row past the
                    // others = the edit drop row.
                    const maxRow = QsGrid.rowsOf(root.layout.items.filter(i => i.id !== modelData));
                    const cx = Math.max(0, Math.min(root._cols - r.w, Math.round((grabOrigin.x + dx) / root._pitch)));
                    const cy = Math.max(0, Math.min(maxRow, Math.round((grabOrigin.y + dy) / root._pitch)));
                    root.layout.previewMove(modelData, cx, cy);
                }
                onMoveEnded: {
                    root.layout.commit();
                    animate = true;
                    follow = false;
                    root.activeId = "";
                }

                onResizeStarted: {
                    root.activeId = modelData;
                    grabOrigin = Qt.point(width, height);
                }
                onResizeUpdated: (dx, dy) => {
                    const wantW = (grabOrigin.x + dx + root._spacing) / root._pitch;
                    const wantH = (grabOrigin.y + dy + root._spacing) / root._pitch;
                    const s = QsGrid.nearestSize(DashCatalog.sizesOf(modelData).filter(s => s[0] <= root._cols), wantW, wantH);
                    root.layout.previewResize(modelData, s[0], s[1]);
                }
                onResizeEnded: {
                    root.layout.commit();
                    root.activeId = "";
                }
            }
        }
    }

    QsEditFooter {
        x: root._margins
        y: grid.y + grid.height + root._spacing
        width: grid.width
        height: DashMetrics.footerHeight(root.dash ?? {}, root.layout?.hiddenIds.length ?? 0)
        cfg: root.editCfg
        theme: root.theme
        hiddenIds: root.layout?.hiddenIds ?? []
        glyphOf: id => DashCatalog.glyphOf(id)
        opacity: root.editing ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { Spring { eps: 0.01 } }
        onAddRequested: id => root.layout.add(id)
        onDoneRequested: root.layout.endEdit()
    }

    // Card contents, bound to the services ---------------------------------

    Component {
        id: calendarComp
        CalendarCard {
            clock: root.clock
            theme: root.theme
            dash: root.dash
        }
    }
    Component {
        id: weatherComp
        WeatherCard {
            weather: root.weather
            clock: root.clock
            theme: root.theme
            dash: root.dash
        }
    }
    Component {
        id: mediaComp
        MediaCard {
            players: root.players
            theme: root.theme
            dash: root.dash
        }
    }
    Component {
        id: systemComp
        SystemLoadCard {
            systemUsage: root.systemUsage
            theme: root.theme
            dash: root.dash
        }
    }
    Component {
        id: batteryComp
        BatteryCard {
            battery: root.battery
            theme: root.theme
            dash: root.dash
        }
    }
    Component {
        id: sensorsComp
        SensorsCard {
            sensors: root.sensors
            theme: root.theme
            dash: root.dash
        }
    }
    Component {
        id: processesComp
        ProcessesCard {
            systemUsage: root.systemUsage
            theme: root.theme
            dash: root.dash
        }
    }
    Component {
        id: updatesComp
        UpdatesCard {
            theme: root.theme
            dash: root.dash
        }
    }
    Component {
        id: eventsComp
        EventsCard {
            theme: root.theme
            dash: root.dash
        }
    }
}
