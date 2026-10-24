import QtQuick
import Quickshell
import Quickshell.Widgets

// Notification ticker in the Minimal-revealed bar (fullscreen, spec): the bar
// grows by `reserve` on the left and this item sits in that room — sender
// avatar / app icon standing still (the bar's music cover size, user), the
// text scrolling past it in a clipped viewport. Text that fits stays put;
// longer text loops (a second copy follows `loopGap` behind), edges fade into
// the island body. `showMs` = how long the ticker should stay so at least one
// full pass is seen (Island's tickerTimer follows it).
Item {
    id: root
    property var notif: null
    property var cfg: null          // Config notifications
    property var theme: null
    property real iconSize: 24
    property color fadeColor: "black"
    property bool running: false
    // Privacy (Notifications.redact): the app name only.
    property bool redacted: false

    readonly property real gap: root.cfg?.tickerIconGap ?? 8
    // Viewport fits short text, capped at tickerWidth (longer text scrolls).
    readonly property real viewportWidth: Math.ceil(Math.min(root.cfg?.tickerWidth ?? 220, line.width))
    // Room the bar must add for the ticker (icon + gap + viewport + gap to the row).
    readonly property real reserve: root.iconSize + root.gap + root.viewportWidth + (root.cfg?.tickerRowGap ?? 12)

    readonly property string appName: root.notif?.appName ?? ""
    readonly property string image: root.redacted ? "" : (root.notif?.image ?? "")
    readonly property string appIcon: root.notif?.appIcon ?? ""
    readonly property string summary: (root.redacted ? "" : (root.notif?.summary ?? "")).replace(/\s+/g, " ").trim()
    readonly property string body: (root.redacted ? "" : (root.notif?.body ?? "")).replace(/<[^>]*>/g, "").replace(/\s+/g, " ").trim()

    readonly property real loopGap: root.cfg?.tickerLoopGap ?? 48
    readonly property real speed: Math.max(1, root.cfg?.tickerSpeed ?? 60)   // px / s
    readonly property int holdMs: root.cfg?.tickerHoldMs ?? 1200
    readonly property bool scrolls: line.width > (root.cfg?.tickerWidth ?? 220) + 0.5
    readonly property int passMs: Math.round((line.width + root.loopGap) / root.speed * 1000)
    readonly property int showMs: Math.max(root.cfg?.tickerDurationMs ?? 3500,
        root.scrolls ? root.holdMs * 2 + root.passMs : 0)

    // ── Icon: sender avatar, else app icon, else the initial ──
    Item {
        id: iconBox
        width: root.iconSize
        height: root.iconSize
        anchors.verticalCenter: parent.verticalCenter

        ClippingRectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            visible: root.image !== "" && avatar.status !== Image.Error

            Image {
                id: avatar
                anchors.fill: parent
                source: root.image !== "" ? Qt.resolvedUrl(root.image) : ""
                sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
                fillMode: Image.PreserveAspectCrop
                cache: false
                asynchronous: true
            }
        }
        Image {
            id: appIconImg
            anchors.fill: parent
            visible: (root.image === "" || avatar.status === Image.Error) && root.appIcon !== "" && status !== Image.Error
            source: root.appIcon !== "" ? Quickshell.iconPath(root.appIcon, true) : ""
            sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }
        Text {
            anchors.centerIn: parent
            visible: !appIconImg.visible && (root.image === "" || avatar.status === Image.Error)
            text: (root.appName.trim().charAt(0) || "?").toUpperCase()
            color: root.theme?.subtleFg ?? "#B9C0CB"
            font.family: root.theme?.fontFamily ?? ""
            font.pixelSize: Math.round(root.iconSize * 0.5)
            font.weight: Font.DemiBold
        }
    }

    // ── Scrolling text ──
    Item {
        id: viewport
        x: root.iconSize + root.gap
        width: root.viewportWidth
        height: parent.height
        clip: true

        Item {
            id: strip
            height: parent.height
            Row {
                id: line
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Text {
                    id: summaryText
                    text: root.summary !== "" ? root.summary : root.appName
                    color: root.theme?.islandFg ?? "white"
                    font.family: root.theme?.fontFamily ?? ""
                    font.pixelSize: root.theme?.fontSizeBody ?? 12
                    font.weight: Font.DemiBold
                }
                Text {
                    id: bodyText
                    visible: root.body !== ""
                    text: root.body
                    color: root.theme?.subtleFg ?? "#B9C0CB"
                    font.family: root.theme?.fontFamily ?? ""
                    font.pixelSize: root.theme?.fontSizeBody ?? 12
                }
            }
            // Second copy for a seamless loop.
            Row {
                visible: root.scrolls
                x: line.width + root.loopGap
                anchors.verticalCenter: parent.verticalCenter
                spacing: line.spacing
                Text {
                    text: summaryText.text
                    color: summaryText.color
                    font: summaryText.font
                }
                Text {
                    visible: bodyText.visible
                    text: bodyText.text
                    color: bodyText.color
                    font: bodyText.font
                }
            }
        }

        // Marquee: hold, one pass at constant speed (the copy lands where
        // the original started), repeat. Restarted for every notification.
        SequentialAnimation {
            id: marquee
            running: root.running && root.scrolls
            loops: Animation.Infinite
            alwaysRunToEnd: false
            PropertyAction { target: strip; property: "x"; value: 0 }
            PauseAnimation { duration: root.holdMs }
            NumberAnimation {
                target: strip
                property: "x"
                from: 0
                to: -(line.width + root.loopGap)
                duration: root.passMs
            }
        }

        // Soft edges: fade into the island body (only where text is cut).
        Rectangle {
            anchors.left: parent.left
            width: root.cfg?.tickerEdgeFade ?? 14
            height: parent.height
            visible: root.scrolls
            // Only once the text is cut on the left (not during the hold).
            opacity: Math.min(1, -strip.x / Math.max(1, width))
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: root.fadeColor }
                GradientStop { position: 1; color: Qt.rgba(root.fadeColor.r, root.fadeColor.g, root.fadeColor.b, 0) }
            }
        }
        Rectangle {
            anchors.right: parent.right
            width: root.cfg?.tickerEdgeFade ?? 14
            height: parent.height
            visible: root.scrolls
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.rgba(root.fadeColor.r, root.fadeColor.g, root.fadeColor.b, 0) }
                GradientStop { position: 1; color: root.fadeColor }
            }
        }
    }

    onNotifChanged: {
        strip.x = 0;
        if (marquee.running)
            marquee.restart();
    }
}
