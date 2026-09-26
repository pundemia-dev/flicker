import QtQuick

// Gesture hitboxes per spec: bar/clock inside the island, Quick Settings and
// Notification Center strips pressed to the TOP screen edge, adjacent to the
// island's horizontal projection (left = notifications, right = QS), and the
// minimal active zone from the strip (inclusive) to the top screen edge.
//
// IMPORTANT: rendered BELOW the island content (declared before islandRect
// in Island.qml). Presses on indicator/plate areas are consumed by the bar
// content above; this layer only receives presses that fall through the bar
// (gaps, clock text) so gestures and bar clicks coexist.
//
// Gestures handled:
//  - presentation mode: hold LMB on the bar + drag up beyond the island
//  - dashboard drawer: hold LMB on the clock + drag down (island follows the
//    cursor via dashboardDragProgress, snaps on dashboardDragReleased)
//  - Notification Center: hold the top-edge strip left of the island + drag down
//  - Quick Settings: hold the top-edge strip right of the island + drag down
//  - minimal hold: press anywhere in the active zone reveals the bar while
//    held; dragging down commits back to Island; release returns to Minimal
//  - module close: swipe up inside the island while a module is open
Item {
    id: root

    required property bool isMinimal
    required property bool active
    required property bool moduleOpen
    required property real islandX
    required property real islandY
    required property real islandWidth
    required property real islandHeight
    required property var cfg

    signal requestPresentationMinimal()
    signal requestQuickSettings()
    signal requestNotificationCenter()
    signal requestCloseModule()
    signal minimalHoldChanged(bool active)
    signal minimalSwipeDown()
    signal dashboardDragProgress(real dy)
    signal dashboardDragReleased(real dy)

    property real pressX: 0
    property real pressY: 0
    property string zone: ""
    property bool holdActive: false
    property bool swipedDown: false
    property bool fired: false
    property bool dashboardTracking: false
    property bool moduleSwipe: false
    property real maxDy: 0

    readonly property real leftZoneX: root.islandX - root.cfg.notificationsZoneWidth
    readonly property real rightZoneX: root.islandX + root.islandWidth

    MouseArea {
        id: ma
        anchors.fill: parent
        // Keep the grab alive when a drag opens a module mid-gesture
        // (dashboard drawer): `active` flips while the button is held.
        enabled: root.active || ma.pressed
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton

        onPressed: mouse => {
            root.pressX = mouse.x;
            root.pressY = mouse.y;
            root.maxDy = 0;
            root.fired = false;
            root.swipedDown = false;
            root.zone = ma.detectZone(mouse.x, mouse.y);
            root.dashboardTracking = !root.isMinimal && !root.moduleOpen && root.zone === "clock";
            root.moduleSwipe = root.moduleOpen;
            if (root.isMinimal && mouse.y <= root.cfg.minimalActiveZoneHeight) {
                root.holdActive = true;
                root.minimalHoldChanged(true);
            }
        }

        onPositionChanged: mouse => {
            const dy = mouse.y - root.pressY;
            if (dy > root.maxDy)
                root.maxDy = dy;

            // Dashboard drawer: continuous progress, decision on release.
            if (root.dashboardTracking) {
                root.dashboardDragProgress(root.maxDy);
                return;
            }

            // Swipe up inside an open module closes it.
            if (root.moduleSwipe) {
                if (!root.fired && dy < -root.cfg.presentationDragThreshold) {
                    root.fired = true;
                    root.requestCloseModule();
                }
                return;
            }

            // Minimal: hold reveals the bar, a downward drag commits to Island.
            if (root.isMinimal) {
                if (!root.swipedDown && dy > root.cfg.sideDragThreshold) {
                    root.swipedDown = true;
                    root.minimalSwipeDown();
                }
                return;
            }

            if (root.moduleOpen || root.fired)
                return;

            if ((root.zone === "bar" || root.zone === "clock") && dy < -root.cfg.presentationDragThreshold) {
                root.fired = true;
                root.requestPresentationMinimal();
            } else if (root.zone === "left" && dy > root.cfg.sideDragThreshold) {
                root.fired = true;
                root.requestNotificationCenter();
            } else if (root.zone === "right" && dy > root.cfg.sideDragThreshold) {
                root.fired = true;
                root.requestQuickSettings();
            }
        }

        onReleased: mouse => {
            const dy = mouse.y - root.pressY;
            if (dy > root.maxDy)
                root.maxDy = dy;
            if (root.dashboardTracking) {
                root.dashboardTracking = false;
                root.dashboardDragReleased(root.maxDy);
            }
            if (root.holdActive) {
                root.holdActive = false;
                root.minimalHoldChanged(false);
            }
        }

        function detectZone(x: real, y: real): string {
            const inBand = y >= root.islandY && y <= root.islandY + root.islandHeight;
            const inBar = inBand && x >= root.islandX && x <= root.islandX + root.islandWidth;
            if (inBar) {
                const cx = root.islandX + root.islandWidth / 2;
                const cy = root.islandY + root.islandHeight / 2;
                const clockHalfW = root.cfg.clockZoneWidth / 2;
                const clockHalfH = root.cfg.clockZoneHeight / 2;
                if (x >= cx - clockHalfW && x <= cx + clockHalfW
                    && y >= cy - clockHalfH && y <= cy + clockHalfH)
                    return "clock";
                return "bar";
            }

            // Top-edge strips pressed to the screen top (y 0..height) and
            // adjacent to the island's horizontal projection: left strip
            // ends where the island starts, right strip starts where it ends.
            if (y >= 0 && y <= root.cfg.notificationsZoneHeight) {
                if (x >= root.leftZoneX && x < root.islandX)
                    return "left";
            }
            if (y >= 0 && y <= root.cfg.quickSettingsZoneHeight) {
                if (x > root.islandX + root.islandWidth && x <= root.islandX + root.islandWidth + root.cfg.quickSettingsZoneWidth)
                    return "right";
            }
            return "";
        }
    }
}
